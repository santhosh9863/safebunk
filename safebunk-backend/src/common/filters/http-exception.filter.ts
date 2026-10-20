import { ExceptionFilter, Catch, ArgumentsHost, HttpException, HttpStatus } from '@nestjs/common';
import { Response } from 'express';

@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();

    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let message = 'Internal server error';

    if (exception instanceof HttpException) {
      status = exception.getStatus();
      const res = exception.getResponse();
      message = typeof res === 'string' ? res : (res as any).message || exception.message;

      const retryAfterSeconds =
        res && typeof res === 'object'
          ? (res as { retryAfterSeconds?: unknown }).retryAfterSeconds
          : undefined;
      if (
        status === HttpStatus.TOO_MANY_REQUESTS &&
        typeof retryAfterSeconds === 'number' &&
        Number.isFinite(retryAfterSeconds)
      ) {
        response.setHeader(
          'Retry-After',
          String(Math.max(1, Math.ceil(retryAfterSeconds))),
        );
      }
    } else if (exception instanceof Error) {
      message = exception.message;
    }

    response.status(status).json({
      success: false,
      data: null,
      message: Array.isArray(message) ? message.join('; ') : message,
      statusCode: status,
    });
  }
}
