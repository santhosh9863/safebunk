import { Injectable, Logger } from '@nestjs/common';
import { LinwaysService } from '../linways/linways.service';
import { LINWAYS_ENDPOINTS } from '../linways/linways.constants';
import { CacheService } from '../cache/cache.service';

@Injectable()
export class AttendanceService {
  private readonly logger = new Logger(AttendanceService.name);

  constructor(
    private readonly linwaysService: LinwaysService,
    private readonly cacheService: CacheService,
  ) {}

  async getDailyAttendance(
    studentId: string,
    cookies: string,
    fromDate?: string,
    toDate?: string,
  ): Promise<any> {
    const cacheKey = `daily_attendance:${studentId}:${fromDate || ''}:${toDate || ''}`;
    const cached = this.cacheService.get<any>(cacheKey);
    if (cached) return cached;

    const params: Record<string, unknown> = { studentId };
    if (fromDate) params['fromDate'] = fromDate;
    if (toDate) params['toDate'] = toDate;

    const response = await this.linwaysService.get(
      LINWAYS_ENDPOINTS.DAILY_ATTENDANCE,
      params,
      cookies,
    );

    if (response.status !== 200) {
      this.logger.warn(`Daily attendance fetch failed for ${studentId}`);
      return [];
    }

    this.cacheService.set(cacheKey, response.data, 5 * 60 * 1000);
    return response.data;
  }

  async getSubjectWiseAttendance(studentId: string, cookies: string): Promise<any> {
    const cacheKey = `subject_attendance:${studentId}`;
    const cached = this.cacheService.get<any>(cacheKey);
    if (cached) return cached;

    const response = await this.linwaysService.get(
      LINWAYS_ENDPOINTS.SUBJECT_WISE_ATTENDANCE,
      { studentId },
      cookies,
    );

    if (response.status !== 200) {
      this.logger.warn(`Subject attendance fetch failed for ${studentId}`);
      return [];
    }

    this.cacheService.set(cacheKey, response.data, 5 * 60 * 1000);
    return response.data;
  }
}
