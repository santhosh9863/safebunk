import { RateLimitExceededException } from '../common/exceptions/rate-limit-exceeded.exception';
import {
  LOGIN_RATE_LIMITS,
  LoginRateLimiterService,
} from './login-rate-limiter.service';

class TestLoginRateLimiter extends LoginRateLimiterService {
  nowMs = 1_000_000;

  protected currentTime(): number {
    return this.nowMs;
  }
}

function captureRateLimit(action: () => void): RateLimitExceededException {
  try {
    action();
  } catch (error) {
    expect(error).toBeInstanceOf(RateLimitExceededException);
    return error as RateLimitExceededException;
  }
  throw new Error('Expected the action to be rate limited');
}

describe('LoginRateLimiterService', () => {
  it('blocks the 11th student attempt for the same account across IPs', () => {
    const limiter = new TestLoginRateLimiter();
    const limit = LOGIN_RATE_LIMITS.student.account;

    for (let i = 0; i < limit; i++) {
      limiter.consume('student', `10.0.0.${i}`, 'BCA24XXX');
    }

    expect(() =>
      limiter.consume('student', '10.0.0.99', '  bca24xxx '),
    ).toThrow(RateLimitExceededException);
  });

  it('blocks the 121st student attempt from the same IP across usernames', () => {
    const limiter = new TestLoginRateLimiter();
    const ip = '10.0.0.1';

    for (let i = 0; i < LOGIN_RATE_LIMITS.student.ip; i++) {
      limiter.consume('student', ip, `student-${i}`);
    }

    expect(() => limiter.consume('student', ip, 'another-student')).toThrow(
      RateLimitExceededException,
    );
  });

  it('applies the tighter staff limits per account and per IP', () => {
    const limiter = new TestLoginRateLimiter();

    for (let i = 0; i < LOGIN_RATE_LIMITS.staff.account; i++) {
      limiter.consume('staff', '10.0.0.1', 'campus.admin');
    }
    expect(() => limiter.consume('staff', '10.0.0.2', 'campus.admin')).toThrow(
      RateLimitExceededException,
    );

    const ipLimiter = new TestLoginRateLimiter();
    for (let i = 0; i < LOGIN_RATE_LIMITS.staff.ip; i++) {
      ipLimiter.consume('staff', '10.0.0.1', `staff-${i}`);
    }
    expect(() => ipLimiter.consume('staff', '10.0.0.1', 'one-more')).toThrow(
      RateLimitExceededException,
    );
  });

  it('keeps student and staff buckets separate', () => {
    const limiter = new TestLoginRateLimiter();

    for (let i = 0; i < LOGIN_RATE_LIMITS.student.account; i++) {
      limiter.consume('student', '10.0.0.1', 'shared-name');
    }

    expect(() => limiter.consume('staff', '10.0.0.1', 'shared-name')).not.toThrow();
  });

  it('reports the remaining window and resets after it expires', () => {
    const limiter = new TestLoginRateLimiter();
    const windowMs = LOGIN_RATE_LIMITS.staff.windowMs;

    for (let i = 0; i < LOGIN_RATE_LIMITS.staff.account; i++) {
      limiter.consume('staff', '10.0.0.1', 'campus.admin');
    }

    limiter.nowMs += windowMs - 1;
    const error = captureRateLimit(() =>
      limiter.consume('staff', '10.0.0.1', 'campus.admin'),
    );
    expect(error.getStatus()).toBe(429);
    expect(error.retryAfterSeconds).toBe(1);

    limiter.nowMs += 1;
    expect(() =>
      limiter.consume('staff', '10.0.0.1', 'campus.admin'),
    ).not.toThrow();
  });

  it('does not extend the fixed window when attempts continue during a block', () => {
    const limiter = new TestLoginRateLimiter();
    const rule = LOGIN_RATE_LIMITS.staff;
    const start = limiter.nowMs;

    for (let i = 0; i < rule.account; i++) {
      limiter.consume('staff', '10.0.0.1', 'campus.admin');
    }

    limiter.nowMs = start + rule.windowMs - 1;
    expect(() => limiter.consume('staff', '10.0.0.1', 'campus.admin')).toThrow(
      RateLimitExceededException,
    );

    limiter.nowMs = start + rule.windowMs;
    expect(() =>
      limiter.consume('staff', '10.0.0.1', 'campus.admin'),
    ).not.toThrow();
  });

  it('clears only the account bucket after a successful login', () => {
    const limiter = new TestLoginRateLimiter();

    for (let i = 0; i < LOGIN_RATE_LIMITS.staff.account; i++) {
      limiter.consume('staff', '10.0.0.1', 'campus.admin');
    }

    limiter.resetAccount('staff', '  CAMPUS.ADMIN ');

    expect(() =>
      limiter.consume('staff', '10.0.0.1', 'campus.admin'),
    ).not.toThrow();
    expect(() =>
      limiter.consume('staff', '10.0.0.1', 'another.admin'),
    ).not.toThrow();
  });

  it('keeps the IP bucket after an account reset', () => {
    const limiter = new TestLoginRateLimiter();
    const ip = '10.0.0.1';

    for (let i = 0; i < LOGIN_RATE_LIMITS.staff.ip; i++) {
      limiter.consume('staff', ip, `staff-${i}`);
    }

    limiter.resetAccount('staff', 'staff-0');

    expect(() => limiter.consume('staff', ip, 'fresh-name')).toThrow(
      RateLimitExceededException,
    );
  });

  it('returns a generic response that does not reflect credentials', () => {
    const limiter = new TestLoginRateLimiter();
    const username = 'campus.admin';
    const password = 'super-secret-password';

    for (let i = 0; i < LOGIN_RATE_LIMITS.staff.account; i++) {
      limiter.consume('staff', '10.0.0.1', username);
    }

    const error = captureRateLimit(() =>
      limiter.consume('staff', '10.0.0.1', username),
    );
    const body = error.getResponse() as Record<string, unknown>;

    expect(error.getStatus()).toBe(429);
    expect(body).toEqual({
      statusCode: 429,
      message: 'Too many login attempts. Please try again later.',
      retryAfterSeconds: LOGIN_RATE_LIMITS.staff.windowMs / 1000,
    });
    expect(JSON.stringify(body)).not.toContain(username);
    expect(JSON.stringify(body)).not.toContain(password);
  });
});
