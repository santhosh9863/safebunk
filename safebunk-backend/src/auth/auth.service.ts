import { Injectable, UnauthorizedException, Logger } from '@nestjs/common';
import * as crypto from 'crypto';
import { LinwaysService } from '../linways/linways.service';
import { LINWAYS_ENDPOINTS } from '../linways/linways.constants';
import { CacheService } from '../cache/cache.service';

export interface Session {
  token: string;
  studentId: string;
  username: string;
  cookies: string;
  createdAt: number;
}

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);
  private readonly sessions = new Map<string, Session>();
  private readonly sessionTtlMs = 24 * 60 * 60 * 1000; // 24 hours

  constructor(
    private readonly linwaysService: LinwaysService,
    private readonly cacheService: CacheService,
  ) {}

  async login(username: string, password: string): Promise<{ session: Session; studentInfo: any }> {
    const loginPayload = { username, password };

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
    const sessionToken = this.generateSessionToken();

    const studentInfo = await this.fetchAndCacheStudentInfo(
      username,
      cookieString,
    );

    const session: Session = {
      token: sessionToken,
      studentId: studentInfo.studentId,
      username,
      cookies: cookieString,
      createdAt: Date.now(),
    };

    this.sessions.set(sessionToken, session);

    this.logger.log(`Session created for ${username} (${studentInfo.studentId})`);

    return { session, studentInfo };
  }

  async refreshCookies(username: string, password: string): Promise<string> {
    const loginPayload = { username, password };
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
  }

  async fetchAndCacheStudentInfo(username: string, cookies: string): Promise<any> {
    const cacheKey = `student_info:${username}`;
    const cached = this.cacheService.get<any>(cacheKey);
    if (cached) return cached;

    const response = await this.linwaysService.get(
      LINWAYS_ENDPOINTS.STUDENT_BASIC_DETAILS,
      undefined,
      cookies,
    );

    if (response.status !== 200) {
      throw new UnauthorizedException('Failed to fetch student details from Linways');
    }

    const data = response.data?.data || response.data || {};
    const studentInfo = {
      studentId: String(data.studentId || data.id || ''),
      name: data.name || data.studentName || '',
      batch: data.batch || data.batchName || '',
      username,
    };

    this.cacheService.set(cacheKey, studentInfo, 30 * 60 * 1000);
    return studentInfo;
  }

  private generateSessionToken(): string {
    return crypto.randomBytes(48).toString('hex');
  }
}
