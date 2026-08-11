import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { LinwaysService } from '../linways/linways.service';
import { LINWAYS_ENDPOINTS } from '../linways/linways.constants';
import { CacheService } from '../cache/cache.service';

@Injectable()
export class ProfileService {
  private readonly logger = new Logger(ProfileService.name);

  constructor(
    private readonly linwaysService: LinwaysService,
    private readonly cacheService: CacheService,
  ) {}

  async getProfile(studentId: string, cookies: string): Promise<any> {
    const cacheKey = `profile:${studentId}`;
    const cached = this.cacheService.get<any>(cacheKey);
    if (cached) return cached;

    const response = await this.linwaysService.get(
      LINWAYS_ENDPOINTS.STUDENT_BASIC_DETAILS,
      { studentId },
      cookies,
    );

    if (response.status !== 200) {
      this.logger.warn(`Profile fetch failed for student ${studentId}`);
      throw new NotFoundException('Profile not found');
    }

    const raw = response.data?.data || response.data;
    const profile = {
      studentId: String(raw.studentId || raw.id || ''),
      name: raw.name || raw.studentName || '',
      batch: raw.batch || raw.batchName || '',
      batchId: raw.batchId || '',
      course: raw.course || raw.courseName || '',
      semester: raw.semester || raw.currentSemester || '',
      rollNo: raw.rollNo || raw.rollNumber || '',
      email: raw.email || '',
      phone: raw.phone || raw.mobile || '',
      profileImage: raw.profileImage || raw.photo || null,
    };

    this.cacheService.set(cacheKey, profile, 10 * 60 * 1000);
    return profile;
  }
}
