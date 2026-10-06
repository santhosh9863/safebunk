import { NotFoundException } from '@nestjs/common';
import { ReportsService } from './reports.service';
import { CreateReportDto } from './dto/create-report.dto';

/** Minimal in-memory stand-in for the Prisma report model. */
class FakePrisma {
  rows: any[] = [];
  private seq = 0;

  report = {
    create: jest.fn(async ({ data }: any) => {
      if (this.rows.some((r) => r.code === data.code)) {
        throw new Error('Unique constraint failed on code');
      }
      const row = {
        id: `rep_${++this.seq}`,
        aiCategory: null,
        aiPriority: null,
        aiConfidence: null,
        aiReasons: null,
        aiOverrideBy: null,
        aiOverrideAt: null,
        resolvedAt: null,
        createdAt: new Date(Date.UTC(2026, 9, 6, 10, 0, this.seq)),
        updatedAt: new Date(Date.UTC(2026, 9, 6, 10, 0, this.seq)),
        ...data,
      };
      this.rows.push(row);
      return row;
    }),
    count: jest.fn(async () => this.rows.length),
    findMany: jest.fn(async ({ where, orderBy }: any) => {
      let out = this.rows.filter((r) =>
        Object.entries(where).every(([k, v]) => r[k] === v),
      );
      if (orderBy?.createdAt === 'desc') {
        out = [...out].sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
      }
      return out;
    }),
    findFirst: jest.fn(async ({ where }: any) => {
      return this.rows.find((r) => Object.entries(where).every(([k, v]) => r[k] === v)) ?? null;
    }),
  };
}

const baseDto = (over: Partial<CreateReportDto> = {}): CreateReportDto => ({
  title: 'Water Leakage',
  description: 'Water leaking near the electrical panel on the second floor.',
  location: 'Block B · 2nd Floor',
  category: 'Infrastructure',
  ...over,
});

describe('ReportsService', () => {
  let prisma: FakePrisma;
  let service: ReportsService;

  beforeEach(() => {
    prisma = new FakePrisma();
    service = new ReportsService(prisma as any);
  });

  describe('createReport', () => {
    it('creates a SUBMITTED report owned by the authenticated student', async () => {
      const report = await service.createReport('4301', baseDto());

      expect(report.studentId).toBe('4301');
      expect(report.status).toBe('SUBMITTED');
      expect(report.code).toMatch(/^PULSE-\d+$/);
      expect(report.title).toBe('Water Leakage');
      expect(report.location).toBe('Block B · 2nd Floor');
      expect(report.priority).toBe('MEDIUM');
      expect(report.resolvedAt).toBeNull();
      expect(report.assignedDepartment).toBeNull();
    });

    it('leaves every AI field null (no ML in Phase 1)', async () => {
      const report = await service.createReport('4301', baseDto());
      expect(report.aiCategory).toBeNull();
      expect(report.aiPriority).toBeNull();
      expect(report.aiConfidence).toBeNull();
      expect(report.aiDepartment).toBeNull();
      expect(report.aiReasons).toBeNull();
    });

    it('honors an explicit priority and defaults otherwise', async () => {
      const high = await service.createReport('4301', baseDto({ priority: 'HIGH' }));
      expect(high.priority).toBe('HIGH');

      const defaulted = await service.createReport('4301', baseDto());
      expect(defaulted.priority).toBe('MEDIUM');
    });

    it('assigns sequential unique codes', async () => {
      const a = await service.createReport('4301', baseDto());
      const b = await service.createReport('4302', baseDto());
      expect(a.code).not.toBe(b.code);
    });
  });

  describe('listMyReports', () => {
    it('returns only the authenticated student’s reports, newest first', async () => {
      await service.createReport('4301', baseDto({ title: 'Mine old' }));
      await service.createReport('9999', baseDto({ title: 'Someone else' }));
      await service.createReport('4301', baseDto({ title: 'Mine new' }));

      const mine = await service.listMyReports('4301');
      expect(mine).toHaveLength(2);
      expect(mine.every((r) => r.title.startsWith('Mine'))).toBe(true);
      expect(mine[0].title).toBe('Mine new');
    });

    it('returns an empty list for a student with no reports', async () => {
      await service.createReport('4301', baseDto());
      expect(await service.listMyReports('7777')).toEqual([]);
    });
  });

  describe('getOwnedReport — IDOR protection', () => {
    it('returns a report the student owns', async () => {
      const created = await service.createReport('4301', baseDto());
      const found = await service.getOwnedReport('4301', created.id);
      expect(found.id).toBe(created.id);
      expect(found.code).toBe(created.code);
    });

    it('throws NotFoundException for another student’s report (no existence leak)', async () => {
      const created = await service.createReport('4301', baseDto());
      await expect(service.getOwnedReport('9999', created.id)).rejects.toThrow(
        NotFoundException,
      );
      // Same error as a truly missing id — no oracle distinguishing the two.
      await expect(service.getOwnedReport('9999', 'does-not-exist')).rejects.toThrow(
        NotFoundException,
      );
    });

    it('throws NotFoundException for a missing id', async () => {
      await expect(service.getOwnedReport('4301', 'nope')).rejects.toThrow(
        NotFoundException,
      );
    });
  });

  describe('ownership source', () => {
    it('never reads studentId from the DTO — client-supplied ids are absent', async () => {
      // The DTO class declares no studentId property; the global pipe runs
      // with whitelist + forbidNonWhitelisted, so a client sending studentId
      // is rejected before reaching the service. Assert the shape contract.
      const dto = baseDto();
      expect(Object.keys(dto)).not.toContain('studentId');

      // Even a hand-built object carrying a spoofed studentId cannot change
      // ownership: the service takes studentId only from its 1st argument.
      const spoofed = { ...dto, studentId: '9999' } as unknown as CreateReportDto;
      const report = await service.createReport('4301', spoofed);
      expect(report.studentId).toBe('4301');
    });
  });
});
