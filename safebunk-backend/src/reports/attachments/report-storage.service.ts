import {
  BadGatewayException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { createClient, SupabaseClient } from '@supabase/supabase-js';

/** Private bucket that holds report photos. */
const DEFAULT_BUCKET = 'report-attachments';

/**
 * Object storage for report photos, backed by **Supabase Storage** (private
 * bucket) via the server-side service-role key. The service-role key lives only
 * on the backend; Flutter never talks to Supabase directly.
 *
 * The adapter exposes the same tiny surface the attachments service already
 * uses (put/get/remove) and keeps the same guarantees: there is deliberately NO
 * local-disk fallback, and when configuration is missing `isConfigured()` is
 * false so every operation throws 503 instead of degrading silently.
 */
@Injectable()
export class ReportStorageService {
  private readonly logger = new Logger(ReportStorageService.name);
  private client: SupabaseClient | null = null;

  private get bucket(): string {
    return process.env.SUPABASE_STORAGE_BUCKET || DEFAULT_BUCKET;
  }

  private resolveClient(): SupabaseClient | null {
    if (this.client) return this.client;

    const url = process.env.SUPABASE_URL;
    const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!url || !serviceRoleKey) return null;

    try {
      this.client = createClient(url, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      return this.client;
    } catch (error) {
      this.logger.error(`Supabase client initialization failed: ${error}`);
      return null;
    }
  }

  /** True when Supabase Storage is configured and usable. */
  isConfigured(): boolean {
    return this.resolveClient() !== null;
  }

  private storage() {
    const client = this.resolveClient();
    if (!client) {
      throw new ServiceUnavailableException(
        'Image storage is not configured. Set SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY ' +
          `and SUPABASE_STORAGE_BUCKET (bucket "${this.bucket}").`,
      );
    }
    return client.storage.from(this.bucket);
  }

  async put(path: string, data: Buffer, contentType: string): Promise<void> {
    const { error } = await this.storage().upload(path, data, {
      contentType,
      upsert: false,
      cacheControl: 'private, max-age=0, no-store',
    });
    if (error) throw this.fail('upload', error);
  }

  async get(path: string): Promise<Buffer> {
    const { data, error } = await this.storage().download(path);
    if (error || !data) throw this.fail('download', error);
    return Buffer.from(await data.arrayBuffer());
  }

  async remove(path: string): Promise<void> {
    const { error } = await this.storage().remove([path]);
    if (error) throw this.fail('remove', error);
  }

  private fail(action: string, error: unknown): BadGatewayException {
    this.logger.error(`Supabase Storage ${action} failed: ${describe(error)}`);
    return new BadGatewayException('Image storage is temporarily unavailable.');
  }
}

function describe(error: unknown): string {
  if (!error) return 'unknown error';
  if (typeof error === 'object' && 'message' in error) {
    return String((error as { message: unknown }).message);
  }
  return String(error);
}
