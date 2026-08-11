import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import * as fs from 'fs';
import * as path from 'path';

/**
 * Zero-dependency JSON-file persistence for the notification system.
 *
 * The backend currently has no database; this store keeps device
 * registrations, preferences, dedup markers and watcher baselines across
 * restarts. Writes are atomic (temp file + rename) and debounced so the
 * every-minute/5-minute cron jobs do not thrash the disk.
 */
@Injectable()
export class JsonStoreService implements OnModuleDestroy {
  private readonly logger = new Logger(JsonStoreService.name);
  private readonly filePath: string;
  private data: Record<string, unknown> = {};
  private loaded = false;
  private writeTimer: NodeJS.Timeout | null = null;

  constructor() {
    const configured = process.env.PULSE_STORE_PATH;
    this.filePath = configured
      ? path.resolve(configured)
      : path.resolve(process.cwd(), 'data', 'pulse-store.json');
  }

  get<T>(key: string): T | null {
    this.ensureLoaded();
    const value = this.data[key];
    return value === undefined ? null : (value as T);
  }

  /** Get a value, returning a provided default when missing. */
  getOr<T>(key: string, fallback: T): T {
    const value = this.get<T>(key);
    return value === null || value === undefined ? fallback : value;
  }

  set(key: string, value: unknown): void {
    this.ensureLoaded();
    this.data[key] = value;
    this.scheduleWrite();
  }

  delete(key: string): void {
    this.ensureLoaded();
    if (key in this.data) {
      delete this.data[key];
      this.scheduleWrite();
    }
  }

  onModuleDestroy(): void {
    if (this.writeTimer) {
      clearTimeout(this.writeTimer);
      this.writeTimer = null;
    }
    if (this.loaded) {
      this.flush();
    }
  }

  private ensureLoaded(): void {
    if (this.loaded) return;
    this.loaded = true;
    try {
      if (fs.existsSync(this.filePath)) {
        const raw = fs.readFileSync(this.filePath, 'utf-8');
        this.data = raw.trim() ? JSON.parse(raw) : {};
      } else {
        fs.mkdirSync(path.dirname(this.filePath), { recursive: true });
        this.data = {};
      }
    } catch (error) {
      this.logger.warn(`Failed to load store at ${this.filePath}: ${error}`);
      this.data = {};
    }
  }

  private scheduleWrite(): void {
    if (this.writeTimer) return;
    this.writeTimer = setTimeout(() => {
      this.writeTimer = null;
      this.flush();
    }, 250);
  }

  private flush(): void {
    try {
      fs.mkdirSync(path.dirname(this.filePath), { recursive: true });
      const tempPath = `${this.filePath}.tmp`;
      fs.writeFileSync(tempPath, JSON.stringify(this.data, null, 2), 'utf-8');
      fs.renameSync(tempPath, this.filePath);
    } catch (error) {
      this.logger.error(`Failed to persist store: ${error}`);
    }
  }
}
