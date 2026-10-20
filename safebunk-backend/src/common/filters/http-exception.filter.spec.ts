import { ArgumentsHost, HttpStatus } from '@nestjs/common';
import { AllExceptionsFilter } from './http-exception.filter';
import { RateLimitExceededException } from '../exceptions/rate-limit-exceeded.exception';

function makeHost() {
  const json = jest.fn();
  const response = {
    status: jest.fn(),
    json,
    setHeader: jest.fn(),
  };
  response.status.mockReturnValue(response);

  const host = {
    switchToHttp: () => ({ getResponse: () => response }),
  } as unknown as ArgumentsHost;

  return { host, response, json };
}

describe('AllExceptionsFilter', () => {
  it('sets Retry-After and keeps the 429 body free of credentials', () => {
    const { host, response, json } = makeHost();
    const filter = new AllExceptionsFilter();

    filter.catch(new RateLimitExceededException(120), host);

    expect(response.status).toHaveBeenCalledWith(
      HttpStatus.TOO_MANY_REQUESTS,
    );
    expect(response.setHeader).toHaveBeenCalledWith('Retry-After', '120');
    expect(json).toHaveBeenCalledWith({
      success: false,
      data: null,
      message: 'Too many login attempts. Please try again later.',
      statusCode: HttpStatus.TOO_MANY_REQUESTS,
    });
    expect(JSON.stringify(json.mock.calls[0][0])).not.toContain('password');
    expect(JSON.stringify(json.mock.calls[0][0])).not.toContain('username');
  });
});
