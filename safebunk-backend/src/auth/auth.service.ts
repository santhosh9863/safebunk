import { Injectable, UnauthorizedException, Logger } from '@nestjs/common';
import * as crypto from 'crypto';
import { LinwaysService } from '../linways/linways.service';
import { LINWAYS_ENDPOINTS } from '../linways/linways.constants';
import { CacheService } from '../cache/cache.service';
import { JsonStoreService } from '../common/store/json-store.service';
import { normalizeGender } from '../profile/profile.service';

export interface Session {
  token: string;
  studentId: string;
  username: string;
  cookies: string;
  authToken: string;
  createdAt: number;
}

const STORE_SESSIONS = 'authSessions';

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);
  private readonly sessions = new Map<string, Session>();
  private readonly sessionTtlMs = 24 * 60 * 60 * 1000; // 24 hours

  constructor(
    private readonly linwaysService: LinwaysService,
    private readonly cacheService: CacheService,
    private readonly store: JsonStoreService,
  ) {
    // Restore sessions from disk so the background notification watchers
    // keep working across backend restarts/redeploys.
    this.restoreSessions();
  }

  private restoreSessions(): void {
    try {
      const stored = this.store.get<Session[]>(STORE_SESSIONS) ?? [];
      const now = Date.now();
      let restored = 0;
      for (const session of stored) {
        if (!session?.token || !session?.studentId || !session?.cookies || !session?.authToken) continue;
        if (now - session.createdAt > this.sessionTtlMs) continue;
        this.sessions.set(session.token, session);
        restored++;
      }
      if (restored > 0) {
        this.logger.log(`Restored ${restored} session(s) from store`);
      }
    } catch (error) {
      this.logger.warn(`Failed to restore sessions: ${error}`);
    }
  }

  private persistSessions(): void {
    this.store.set(STORE_SESSIONS, Array.from(this.sessions.values()));
  }

  async login(username: string, password: string): Promise<{ session: Session; studentInfo: any }> {
    const loginPayload = { username, password, next: '', userType: 'STUDENT' };

    this.logger.log(`Attempting Linways login for ${username}`);

    const response = await this.linwaysService.post(LINWAYS_ENDPOINTS.LOGIN, loginPayload);

    if (response.status !== 200) {
      this.logger.warn(`Linways login failed for ${username}: status ${response.status}`);
      throw new UnauthorizedException(
        response.data?.message || 'Invalid credentials or Linways login failed',
      );
    }

    const cookies = this.linwaysService.extractCookies(response);
    const cookieString = this.linwaysService.mergeCookies(undefined, cookies);

    const authToken = String(response.data?.data?.accessToken ?? '');
    if (!authToken) {
      this.logger.warn(`Linways login for ${username} returned no accessToken`);
      throw new UnauthorizedException('Linways login did not return an access token');
    }

    const studentId = this.decodeJwtUserId(authToken) || username;

    const sessionToken = this.generateSessionToken();

    const studentInfo = await this.fetchAndCacheStudentInfo(
      username,
      cookieString,
      authToken,
      studentId,
    );

    const session: Session = {
      token: sessionToken,
      studentId: studentInfo.studentId,
      username,
      cookies: cookieString,
      authToken,
      createdAt: Date.now(),
    };

    this.sessions.set(sessionToken, session);
    this.persistSessions();

    this.logger.log(`Session created for ${username} (${studentInfo.studentId})`);

    return { session, studentInfo };
  }

  async refreshCookies(username: string, password: string): Promise<string> {
    const loginPayload = { username, password, next: '', userType: 'STUDENT' };
    const response = await this.linwaysService.post(LINWAYS_ENDPOINTS.LOGIN, loginPayload);

    if (response.status !== 200) {
      throw new UnauthorizedException('Failed to refresh Linways session');
    }

    const cookies = this.linwaysService.extractCookies(response);
    return this.linwaysService.mergeCookies(undefined, cookies);
  }

  validateSession(token: string): Session | null {
    const session = this.sessions.get(token);
    if (!session) return null;

    if (Date.now() - session.createdAt > this.sessionTtlMs) {
      this.sessions.delete(token);
      return null;
    }

    return session;
  }

  async logout(token: string): Promise<void> {
    this.sessions.delete(token);
    this.persistSessions();
  }

  /** All non-expired sessions — used by the background notification watchers. */
  getActiveSessions(): Session[] {
    const now = Date.now();
    const active: Session[] = [];
    let pruned = false;
    for (const [token, session] of this.sessions.entries()) {
      if (now - session.createdAt > this.sessionTtlMs) {
        this.sessions.delete(token);
        pruned = true;
        continue;
      }
      active.push(session);
    }
    if (pruned) this.persistSessions();
    return active;
  }

  async fetchAndCacheStudentInfo(
    username: string,
    cookies: string,
    authToken: string,
    studentId: string,
  ): Promise<any> {
    const cacheKey = `student_info:${username}`;
    const cached = this.cacheService.get<any>(cacheKey);
    if (cached) return cached;

    const response = await this.linwaysService.get(
      LINWAYS_ENDPOINTS.STUDENT_BASIC_DETAILS,
      { studentId },
      cookies,
      authToken,
    );

    if (response.status !== 200) {
      throw new UnauthorizedException('Failed to fetch student details from Linways');
    }

    const data = response.data?.data || response.data || {};
    const studentInfo = {
      studentId: String(data.studentId || data.id || studentId || ''),
      name: data.name || data.studentName || '',
      gender: normalizeGender(data.gender || data.genderName || data.sex),
      batch: data.batch || data.batchName || '',
      username,
    };

    this.cacheService.set(cacheKey, studentInfo, 30 * 60 * 1000);
    return studentInfo;
  }

  /** Decodes the `userId` from a Linways JWT's payload (base64url). */
  private decodeJwtUserId(token: string): string | null {
    try {
      const parts = token.split('.');
      if (parts.length !== 3) return null;
      const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
      return String(payload?.data?.userId ?? '') || null;
    } catch {
      return null;
    }
  }

  private generateSessionToken(): string {
    return crypto.randomBytes(48).toString('hex');
  }
}
