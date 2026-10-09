import { BadRequestException } from '@nestjs/common';
import { ReportsService } from './reports.service';
import { CreateReportDto } from './dto/create-report.dto';

class FakePrisma {
  reports: any[] = [];
  attachments: any[] = [];
  private seq = 0;

  report = {
    create: jest.fn(async ({ data }: any) => {
      const row = {
        id: `rep_${++this.seq}`,
        aiCategory: null,
        aiPriority: null,
        aiConfidence: null,
        aiDepartment: null,
        aiReasons: null,
        resolvedAt: null,
        createdAt: new Date(),
        updatedAt: new Date(),
        ...data,
      };
      this.reports.push(row);
      return row;
    }),
    count: jest.fn(async () => this.reports.length),
    update: jest.fn(async ({ where, data }: any) => {
      const row = this.reports.find((r) => r.id === where.id);
      Object.assign(row, data);
      return row;
    }),
    delete: jest.fn(async ({ where }: any) => {
      const i = this.reports.findIndex((r) => r.id === where.id);
      const [row] = this.reports.splice(i, 1);
      return row;
    }),
    findMany: jest.fn(),
    findFirst: jest.fn(),
  };

  attachment = {
    findFirst: jest.fn(async ({ where }: any) => {
      return this.attachments.find((a) => Object.entries(where).every(([k, v]) => a[k] === v)) ?? null;
    }),
  };
}

const dto = (over: Partial<CreateReportDto> = {}): CreateReportDto => ({
  title: 'Burst pipe',
  description: 'Water everywhere near the lab entrance.',
  ...over,
});

describe('ReportsService — attachment association', () => {
  let prisma: FakePrisma;
  let claimForReport: jest.Mock;
  let service: ReportsService;

  beforeEach(() => {
    prisma = new FakePrisma();
    claimForReport = jest.fn(async () => true);
    service = new ReportsService(prisma as any, { claimForReport } as any);
  });

  it('leaves imageUrl null and does not claim anything without an attachmentId', async () => {
    const report = await service.createReport('4301', dto());
    expect(report.imageUrl).toBeNull();
    expect(claimForReport).not.toHaveBeenCalled();
  });

  it('claims a valid attachment and stores the server-derived URL', async () => {
    prisma.attachments.push({ id: 'att_1', studentId: '4301', reportId: null });

    const report = await service.createReport('4301', dto({ attachmentId: 'att_1' }));

    expect(claimForReport).toHaveBeenCalledWith('4301', 'att_1', report.id);
    expect(report.imageUrl).toBe('/api/reports/attachments/att_1');
    expect(prisma.report.update).toHaveBeenCalledWith({
      where: { id: report.id },
      data: { imageUrl: '/api/reports/attachments/att_1' },
    });
  });

  it("rejects an attachment owned by another student before creating a report", async () => {
    prisma.attachments.push({ id: 'att_1', studentId: '9999', reportId: null });

    await expect(service.createReport('4301', dto({ attachmentId: 'att_1' }))).rejects.toThrow(
      BadRequestException,
    );
    expect(prisma.report.create).not.toHaveBeenCalled();
  });

  it('rejects an attachment that is already linked to a report', async () => {
    prisma.attachments.push({ id: 'att_1', studentId: '4301', reportId: 'rep_x' });

    await expect(service.createReport('4301', dto({ attachmentId: 'att_1' }))).rejects.toThrow(
      BadRequestException,
    );
    expect(prisma.report.create).not.toHaveBeenCalled();
  });

  it('rolls back the report when the attachment claim loses a race', async () => {
    prisma.attachments.push({ id: 'att_1', studentId: '4301', reportId: null });
    claimForReport.mockResolvedValueOnce(false);

    await expect(service.createReport('4301', dto({ attachmentId: 'att_1' }))).rejects.toThrow(
      BadRequestException,
    );
    expect(prisma.report.delete).toHaveBeenCalledTimes(1);
    expect(prisma.reports).toHaveLength(0);
  });
});
