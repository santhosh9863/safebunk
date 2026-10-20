import { Injectable } from '@nestjs/common';
import { RateLimitExceededException } from '../common/exceptions/rate-limit-exceeded.exception';

export type LoginScope = 'student' | 'staff';

export interface LoginRateLimitRule {
  /** Maximum attempts per client IP within the window. */
  ip: number;
  /** Maximum attempts per (case-insensitive) account within the window. */
  account: number;
  /** Fixed window length in milliseconds. */
  windowMs: number;
}

/**
 * Focused, in-memory login throttling. Both buckets count attempts when they
 * reach the login handler, before credentials are verified, so concurrent
 * requests cannot race past the limit. The account bucket is cleared after a
 * successful login; the IP bucket is not, because otherwise a valid account
 * could be used to reset IP-level protection.
 *
 * This is a temporary throttle, not a permanent account lockout. State is
 * per-process and is lost on restart; a multi-instance deployment needs a
 * shared store (for example Redis) behind the same policy.
 */
export const LOGIN_RATE_LIMITS: Record<LoginScope, LoginRateLimitRule> = {
  student: {
    ip: 120,
    account: 10,
    windowMs: 15 * 60 * 1000,
  },
  staff: {
    ip: 30,
    account: 5,
    windowMs: 15 * 60 * 1000,
  },
};

const SWEEP_INTERVAL_MS = 60 * 1000;

interface AttemptBucket {
  count: number;
  resetAt: number;
}

@Injectable()
export class LoginRateLimiterService {
  private readonly buckets = new Map<string, AttemptBucket>();
  private lastSweepAt = 0;

  /**
   * Records an attempt or throws a 429 if either the per-IP or per-account
   * bucket is already at its limit. Call this synchronously at the start of
   * the login handler.
   */
  consume(scope: LoginScope, ip: string, username: string): void {
    const now = this.currentTime();
    const rule = LOGIN_RATE_LIMITS[scope];
    const account = this.normalizeUsername(username);

    this.sweep(now);

    const buckets = [
      { key: `${scope}:ip:${ip || 'unknown'}`, limit: rule.ip },
      { key: `${scope}:account:${account}`, limit: rule.account },
    ];

    let retryAfterMs = 0;
    for (const { key, limit } of buckets) {
      const bucket = this.buckets.get(key);
      if (!bucket || now >= bucket.resetAt) continue;
      if (bucket.count >= limit) {
        retryAfterMs = Math.max(retryAfterMs, bucket.resetAt - now);
      }
    }

    if (retryAfterMs > 0) {
      throw new RateLimitExceededException(Math.ceil(retryAfterMs / 1000));
    }

    for (const { key, limit } of buckets) {
      const bucket = this.buckets.get(key);
      if (!bucket || now >= bucket.resetAt) {
        this.buckets.set(key, {
          count: 1,
          resetAt: now + rule.windowMs,
        });
        continue;
      }
      // The limit check above guarantees this stays within the limit.
      bucket.count = Math.min(bucket.count + 1, limit);
    }
  }

  /** Clears the account bucket after successful authentication. */
  resetAccount(scope: LoginScope, username: string): void {
    this.buckets.delete(
      `${scope}:account:${this.normalizeUsername(username)}`,
    );
  }

  /** Test seam for time-dependent window tests. */
  protected currentTime(): number {
    return Date.now();
  }

  private normalizeUsername(username: string): string {
    return (username ?? '').trim().toLowerCase();
  }

  private sweep(now: number): void {
    if (now - this.lastSweepAt < SWEEP_INTERVAL_MS) return;
    this.lastSweepAt = now;

    for (const [key, bucket] of this.buckets) {
      if (now >= bucket.resetAt) {
        this.buckets.delete(key);
      }
    }
  }
}
