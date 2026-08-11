import { Injectable, Logger } from '@nestjs/common';
import { LinwaysService } from '../linways/linways.service';
import { LINWAYS_ENDPOINTS } from '../linways/linways.constants';
import { CacheService } from '../cache/cache.service';

@Injectable()
export class TimetableService {
  private readonly logger = new Logger(TimetableService.name);

  constructor(
    private readonly linwaysService: LinwaysService,
    private readonly cacheService: CacheService,
  ) {}

  async getTodaySchedule(studentId: string, cookies: string): Promise<any> {
    const cacheKey = 'today_schedule:' + studentId;
    const cached = this.cacheService.get<any>(cacheKey);
    if (cached) return cached;

    const response = await this.linwaysService.get(
      LINWAYS_ENDPOINTS.STUDENT_DAILY_SCHEDULE,
      { studentId },
      cookies,
    );

    if (response.status !== 200) {
      this.logger.warn('Today schedule fetch failed for ' + studentId);
      return [];
    }

    this.cacheService.set(cacheKey, response.data, 2 * 60 * 1000);
    return response.data;
  }

  async getWeeklyTimetable(
    batchId: string,
    fromDate: string,
    toDate: string,
    cookies: string,
  ): Promise<any> {
    const cacheKey = 'weekly_timetable:' + batchId + ':' + fromDate + ':' + toDate;
    const cached = this.cacheService.get<any>(cacheKey);
    if (cached) return cached;

    const response = await this.linwaysService.get(
      LINWAYS_ENDPOINTS.TIMETABLE,
      {
        getDaywise: true,
        batchId,
        fromDate,
        toDate,
      },
      cookies,
    );

    if (response.status !== 200) {
      this.logger.warn('Weekly timetable fetch failed for batch ' + batchId);
      return [];
    }

    this.cacheService.set(cacheKey, response.data, 5 * 60 * 1000);
    return response.data;
  }

  async getDayHours(cookies: string): Promise<any> {
    const cacheKey = 'day_hours';
    const cached = this.cacheService.get<any>(cacheKey);
    if (cached) return cached;

    const response = await this.linwaysService.get(
      LINWAYS_ENDPOINTS.DAY_HOURS,
      undefined,
      cookies,
    );

    if (response.status !== 200) {
      this.logger.warn('Day hours fetch failed');
      return [];
    }

    this.cacheService.set(cacheKey, response.data, 30 * 60 * 1000);
    return response.data;
  }

  async getDayOrders(cookies: string): Promise<any> {
    const cacheKey = 'day_orders';
    const cached = this.cacheService.get<any>(cacheKey);
    if (cached) return cached;

    const response = await this.linwaysService.get(
      LINWAYS_ENDPOINTS.DAY_ORDERS,
      undefined,
      cookies,
    );

    if (response.status !== 200) {
      this.logger.warn('Day orders fetch failed');
      return [];
    }

    this.cacheService.set(cacheKey, response.data, 30 * 60 * 1000);
    return response.data;
  }
}
