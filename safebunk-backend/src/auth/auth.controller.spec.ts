import { UnauthorizedException } from '@nestjs/common';
import { AuthController } from './auth.controller';
import {
  LOGIN_RATE_LIMITS,
  LoginRateLimiterService,
} from './login-rate-limiter.service';
import { RateLimitExceededException } from '../common/exceptions/rate-limit-exceeded.exception';

class TestLoginRateLimiter extends LoginRateLimiterService {
  nowMs = 1_000_000;

  protected currentTime(): number {
    return this.nowMs;
  }
}

function makeController() {
  const auth = {
    login: jest.fn(),
  };
  const staffAuth = {
    login: jest.fn(),
  };
  const notifications = {
    getPreferences: jest.fn(() => ({ gender: null })),
    setPreferences: jest.fn(async () => ({})),
  };
  const limiter = new TestLoginRateLimiter();

  return {
    controller: new AuthController(
      auth as any,
      staffAuth as any,
      notifications as any,
      limiter,
    ),
    auth,
    staffAuth,
    notifications,
    limiter,
  };
}

const staffLogin = {
  session: {
    token: 'staff-token',
    role: 'STAFF',
    staffId: 'staff-1',
    username: 'campus.admin',
    createdAt: Date.now(),
  },
  staff: {
    id: 'staff-1',
    username: 'campus.admin',
    displayName: null,
    role: 'STAFF',
  },
};

const studentLogin = {
  session: {
    token: 'student-token',
    role: 'STUDENT',
    studentId: '4301',
    username: 'BCA24XXX',
    cookies: 'session=abc',
    authToken: 'linways-token',
    createdAt: Date.now(),
  },
  studentInfo: {
    studentId: '4301',
    name: 'Student Name',
    gender: null,
    batch: 'BCA 2024',
    username: 'BCA24XXX',
  },
};

async function captureRejection(action: Promise<unknown>): Promise<any> {
  try {
    await action;
  } catch (error) {
    return error;
  }
  throw new Error('Expected the action to reject');
}

describe('AuthController login throttling', () => {
  it('returns a safe 429 after repeated failed staff logins', async () => {
    const { controller, staffAuth } = makeController();
    staffAuth.login.mockRejectedValue(
      new UnauthorizedException('Invalid staff credentials'),
    );

    for (let i = 0; i < LOGIN_RATE_LIMITS.staff.account; i++) {
      await expect(
        controller.staffLogin(
          { username: 'campus.admin', password: 'wrong-password' },
          '10.0.0.1',
        ),
      ).rejects.toThrow(UnauthorizedException);
    }

    const error = await captureRejection(
      controller.staffLogin(
        { username: 'campus.admin', password: 'wrong-password' },
        '10.0.0.1',
      ),
    );

    expect(error).toBeInstanceOf(RateLimitExceededException);
    expect(error.getStatus()).toBe(429);
    expect(error.getResponse()).toEqual({
      statusCode: 429,
      message: 'Too many login attempts. Please try again later.',
      retryAfterSeconds: LOGIN_RATE_LIMITS.staff.windowMs / 1000,
    });
    expect(JSON.stringify(error.getResponse())).not.toContain('campus.admin');
    expect(JSON.stringify(error.getResponse())).not.toContain('wrong-password');
    expect(staffAuth.login).toHaveBeenCalledTimes(
      LOGIN_RATE_LIMITS.staff.account,
    );
  });

  it('returns a safe 429 after repeated failed student logins', async () => {
    const { controller, auth } = makeController();
    auth.login.mockRejectedValue(new UnauthorizedException('Invalid login'));

    for (let i = 0; i < LOGIN_RATE_LIMITS.student.account; i++) {
      await expect(
        controller.login(
          { username: 'BCA24XXX', password: 'wrong-password' },
          '10.0.0.9',
        ),
      ).rejects.toThrow(UnauthorizedException);
    }

    const error = await captureRejection(
      controller.login(
        { username: 'BCA24XXX', password: 'wrong-password' },
        '10.0.0.9',
      ),
    );

    expect(error).toBeInstanceOf(RateLimitExceededException);
    expect(error.getStatus()).toBe(429);
    expect(error.getResponse()).toEqual({
      statusCode: 429,
      message: 'Too many login attempts. Please try again later.',
      retryAfterSeconds: LOGIN_RATE_LIMITS.student.windowMs / 1000,
    });
    expect(JSON.stringify(error.getResponse())).not.toContain('BCA24XXX');
    expect(JSON.stringify(error.getResponse())).not.toContain('wrong-password');
    expect(auth.login).toHaveBeenCalledTimes(LOGIN_RATE_LIMITS.student.account);
  });

  it('does not let one student account lock out staff login', async () => {
    const { controller, auth, staffAuth } = makeController();
    auth.login.mockRejectedValue(new UnauthorizedException('Invalid login'));

    for (let i = 0; i < LOGIN_RATE_LIMITS.student.account; i++) {
      await expect(
        controller.login(
          { username: 'BCA24XXX', password: 'wrong-password' },
          '10.0.0.1',
        ),
      ).rejects.toThrow(UnauthorizedException);
    }

    staffAuth.login.mockResolvedValue(staffLogin);
    const result = await controller.staffLogin(
      { username: 'campus.admin', password: 'correct-password' },
      '10.0.0.1',
    );

    expect(result.success).toBe(true);
    expect(result.data?.staff.role).toBe('STAFF');
  });

  it('clears the account bucket after a successful staff login', async () => {
    const { controller, staffAuth } = makeController();
    staffAuth.login.mockRejectedValue(
      new UnauthorizedException('Invalid staff credentials'),
    );

    for (let i = 0; i < LOGIN_RATE_LIMITS.staff.account - 1; i++) {
      await expect(
        controller.staffLogin(
          { username: 'campus.admin', password: 'wrong-password' },
          '10.0.0.1',
        ),
      ).rejects.toThrow(UnauthorizedException);
    }

    staffAuth.login.mockResolvedValueOnce(staffLogin);
    await expect(
      controller.staffLogin(
        { username: 'campus.admin', password: 'correct-password' },
        '10.0.0.1',
      ),
    ).resolves.toMatchObject({ success: true });

    staffAuth.login.mockRejectedValue(
      new UnauthorizedException('Invalid staff credentials'),
    );
    for (let i = 0; i < LOGIN_RATE_LIMITS.staff.account; i++) {
      await expect(
        controller.staffLogin(
          { username: 'campus.admin', password: 'wrong-password' },
          '10.0.0.1',
        ),
      ).rejects.toThrow(UnauthorizedException);
    }

    await expect(
      controller.staffLogin(
        { username: 'campus.admin', password: 'wrong-password' },
        '10.0.0.1',
      ),
    ).rejects.toThrow(RateLimitExceededException);
  });

  it('clears the account bucket after a successful student login', async () => {
    const { controller, auth } = makeController();
    auth.login.mockRejectedValue(new UnauthorizedException('Invalid login'));

    for (let i = 0; i < LOGIN_RATE_LIMITS.student.account - 1; i++) {
      await expect(
        controller.login(
          { username: 'BCA24XXX', password: 'wrong-password' },
          '10.0.0.3',
        ),
      ).rejects.toThrow(UnauthorizedException);
    }

    auth.login.mockResolvedValueOnce(studentLogin);
    await expect(
      controller.login(
        { username: 'BCA24XXX', password: 'correct-password' },
        '10.0.0.3',
      ),
    ).resolves.toMatchObject({ success: true });

    auth.login.mockRejectedValue(new UnauthorizedException('Invalid login'));
    for (let i = 0; i < LOGIN_RATE_LIMITS.student.account; i++) {
      await expect(
        controller.login(
          { username: 'BCA24XXX', password: 'wrong-password' },
          '10.0.0.3',
        ),
      ).rejects.toThrow(UnauthorizedException);
    }

    await expect(
      controller.login(
        { username: 'BCA24XXX', password: 'wrong-password' },
        '10.0.0.3',
      ),
    ).rejects.toThrow(RateLimitExceededException);
  });

  it('preserves the student login response and gender backfill', async () => {
    const { controller, auth, notifications } = makeController();
    auth.login.mockResolvedValue({
      session: {
        token: 'student-token',
        role: 'STUDENT',
        studentId: '4301',
        username: 'BCA24XXX',
        cookies: 'session=abc',
        authToken: 'linways-token',
        createdAt: Date.now(),
      },
      studentInfo: {
        studentId: '4301',
        name: 'Student Name',
        gender: 'female',
        batch: 'BCA 2024',
        username: 'BCA24XXX',
      },
    });

    const result = await controller.login(
      { username: 'BCA24XXX', password: 'correct-password' },
      '10.0.0.2',
    );

    expect(result.success).toBe(true);
    expect(result.data?.accessToken).toBe('student-token');
    expect(result.data?.student.studentId).toBe('4301');
    expect(notifications.setPreferences).toHaveBeenCalledWith('4301', {
      gender: 'female',
    });
  });
});
