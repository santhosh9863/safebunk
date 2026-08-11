import { Injectable, Logger } from '@nestjs/common';
import { LinwaysService } from '../linways/linways.service';
import { LINWAYS_ENDPOINTS } from '../linways/linways.constants';
import { CacheService } from '../cache/cache.service';

@Injectable()
export class AnalyticsService {
  private readonly logger = new Logger(AnalyticsService.name);

  constructor(
    private readonly linwaysService: LinwaysService,
    private readonly cacheService: CacheService,
  ) {}

  async getHourWiseAttendance(studentId: string, cookies: string): Promise<any> {
    const cacheKey = `hour_attendance:${studentId}`;
    const cached = this.cacheService.get<any>(cacheKey);
    if (cached) return cached;

    const response = await this.linwaysService.get(
      LINWAYS_ENDPOINTS.STUDENT_HOUR_ATTENDANCE,
      { studentId },
      cookies,
    );

    if (response.status !== 200) {
      this.logger.warn(`Hour attendance fetch failed for ${studentId}`);
      return [];
    }

    this.cacheService.set(cacheKey, response.data, 5 * 60 * 1000);
    return response.data;
  }

  async getConsolidatedAnalytics(studentId: string, cookies: string): Promise<any> {
    const cacheKey = `analytics:${studentId}`;
    const cached = this.cacheService.get<any>(cacheKey);
    if (cached) return cached;

    const [subjectAttendance, hourAttendance] = await Promise.all([
      this.getSubjectAttendance(studentId, cookies),
      this.getHourWiseAttendance(studentId, cookies),
    ]);

    const analytics = {
      subjectWise: subjectAttendance,
      hourWise: hourAttendance,
      summary: this.computeSummary(subjectAttendance),
    };

    this.cacheService.set(cacheKey, analytics, 5 * 60 * 1000);
    return analytics;
  }

  private async getSubjectAttendance(studentId: string, cookies: string): Promise<any[]> {
    const response = await this.linwaysService.get(
      LINWAYS_ENDPOINTS.SUBJECT_WISE_ATTENDANCE,
      { studentId },
      cookies,
    );
    return response.data?.data || response.data || [];
  }

  private computeSummary(subjects: any[]): any {
    if (!subjects || subjects.length === 0) {
      return { totalClasses: 0, attended: 0, overallPercentage: 0 };
    }

    let total = 0;
    let attended = 0;

    for (const sub of subjects) {
      total += Number(sub.totalClasses || sub.total || 0);
      attended += Number(sub.attendedClasses || sub.attended || 0);
    }

    return {
      totalClasses: total,
      attended,
      missed: total - attended,
      overallPercentage: total > 0 ? Math.round((attended / total) * 10000) / 100 : 0,
    };
  }
}
