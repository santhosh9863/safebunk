import { readMlClientConfig } from './ml.config';

describe('readMlClientConfig', () => {
  it('requires both the URL and shared token', () => {
    expect(
      readMlClientConfig({
        PULSE_ML_SERVICE_URL: 'http://127.0.0.1:8001',
      }),
    ).toEqual({
      baseUrl: null,
      serviceToken: null,
      timeoutMs: 2_000,
      maxRetries: 1,
    });
  });

  it('normalizes a valid HTTP URL and bounded settings', () => {
    expect(
      readMlClientConfig({
        PULSE_ML_SERVICE_URL: 'http://127.0.0.1:8001///',
        PULSE_ML_SERVICE_TOKEN: 'shared-secret',
        PULSE_ML_TIMEOUT_MS: '1500',
        PULSE_ML_MAX_RETRIES: '2',
      }),
    ).toEqual({
      baseUrl: 'http://127.0.0.1:8001',
      serviceToken: 'shared-secret',
      timeoutMs: 1_500,
      maxRetries: 2,
    });
  });

  it('rejects non-HTTP URLs and embedded credentials', () => {
    for (const url of [
      'ftp://127.0.0.1:8001',
      'http://user:pass@127.0.0.1:8001',
      'http://127.0.0.1:8001?token=leak',
      'not a url',
    ]) {
      expect(
        readMlClientConfig({
          PULSE_ML_SERVICE_URL: url,
          PULSE_ML_SERVICE_TOKEN: 'shared-secret',
        }).baseUrl,
      ).toBeNull();
    }
  });

  it('falls back to safe bounds for malformed numeric settings', () => {
    expect(
      readMlClientConfig({
        PULSE_ML_SERVICE_URL: 'https://ml.internal.example',
        PULSE_ML_SERVICE_TOKEN: 'shared-secret',
        PULSE_ML_TIMEOUT_MS: '999999',
        PULSE_ML_MAX_RETRIES: '-1',
      }),
    ).toEqual({
      baseUrl: 'https://ml.internal.example',
      serviceToken: 'shared-secret',
      timeoutMs: 2_000,
      maxRetries: 1,
    });
  });
});
