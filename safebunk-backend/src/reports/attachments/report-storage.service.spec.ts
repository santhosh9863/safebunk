import { ServiceUnavailableException } from '@nestjs/common';
import { ReportStorageService } from './report-storage.service';

const ENV_KEYS = [
  'SUPABASE_URL',
  'SUPABASE_SERVICE_ROLE_KEY',
  'SUPABASE_STORAGE_BUCKET',
] as const;

describe('ReportStorageService (Supabase configuration)', () => {
  const saved: Record<string, string | undefined> = {};

  beforeEach(() => {
    for (const key of ENV_KEYS) {
      saved[key] = process.env[key];
      delete process.env[key];
    }
  });

  afterEach(() => {
    for (const key of ENV_KEYS) {
      if (saved[key] === undefined) delete process.env[key];
      else process.env[key] = saved[key];
    }
  });

  it('is not configured when the Supabase env vars are missing', async () => {
    const service = new ReportStorageService();
    expect(service.isConfigured()).toBe(false);

    await expect(service.put('p', Buffer.from([1]), 'image/png')).rejects.toThrow(
      ServiceUnavailableException,
    );
    await expect(service.get('p')).rejects.toThrow(ServiceUnavailableException);
    await expect(service.remove('p')).rejects.toThrow(ServiceUnavailableException);
  });

  it('is configured when the URL and service-role key are present', () => {
    process.env.SUPABASE_URL = 'https://example.supabase.co';
    process.env.SUPABASE_SERVICE_ROLE_KEY = 'service-role-key-for-test';
    const service = new ReportStorageService();
    expect(service.isConfigured()).toBe(true);
  });

  it('treats a partial configuration (missing key) as unconfigured', () => {
    process.env.SUPABASE_URL = 'https://example.supabase.co';
    const service = new ReportStorageService();
    expect(service.isConfigured()).toBe(false);
  });
});
