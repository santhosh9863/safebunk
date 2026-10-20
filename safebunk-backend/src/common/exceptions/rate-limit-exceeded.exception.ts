import { HttpException, HttpStatus } from '@nestjs/common';

/**
 * A safe, generic 429 response for throttled authentication attempts.
 *
 * The message deliberately does not echo the username, password or any hint
 * about whether an account exists.
 */
export class RateLimitExceededException extends HttpException {
  readonly retryAfterSeconds: number;

  constructor(retryAfterSeconds: number) {
    const safeRetryAfter = Math.max(1, Math.ceil(retryAfterSeconds));

    super(
      {
        statusCode: HttpStatus.TOO_MANY_REQUESTS,
        message: 'Too many login attempts. Please try again later.',
        retryAfterSeconds: safeRetryAfter,
      },
      HttpStatus.TOO_MANY_REQUESTS,
    );

    this.retryAfterSeconds = safeRetryAfter;
  }
}
