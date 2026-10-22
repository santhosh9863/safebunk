import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import { ReportsService } from './reports.service';
import { CreateReportDto } from './dto/create-report.dto';

type Actor = {
  staffId: string;
  username: string;
  role: 'STAFF' | 'ADMIN';
};

const ADMIN: Actor = {
  staffId: 'admin_1',
  username: 'campus.admin',
  role: 'ADMIN',
};
const STAFF_A: Actor = {
  staffId: 'staff_a',
  username: 'staff.a',
  role: 'STAFF',
};
const STAFF_B: Actor = {
  staffId: 'staff_b',
  username: 'staff.b',
  role: 'STAFF',
};

class FakePrisma {
  reports: any[] = [];
  events: any[] = [];
  staff = [
    {
      id: 'staff_a',
      username: 'staff.a',
      displayName: 'Staff A',
      role: 'STAFF',
      active: true,
    },
    {
      id: 'staff_b',
      username: 'staff.b',
      displayName: 'Staff B',
      role: 'STAFF',
      active: true,
    },
    {
      id: 'staff_inactive',
      username: 'staff.inactive',
      displayName: 'Inactive Staff',
      role: 'STAFF',
      active: false,
    },
    {
      id: 'admin_1',
      username: 'campus.admin',
      displayName: 'Campus Admin',
      role: 'ADMIN',
      active: true,
    },
  ];
  attachments: any[] = [];
  private reportSeq = 0;
  private eventSeq = 0;

  private matches(row: any, where: any = {}): boolean {
    return Object.entries(where).every(([key, condition]) => {
      if (condition && typeof condition === 'object' && 'in' in condition) {
        return (condition.in as unknown[]).includes(row[key]);
      }
      return row[key] === condition;
    });
  }

  private withRelations(row: any, include: any) {
    if (!row) return null;
    const out = { ...row };
    if (include?.assignedStaff) {
      out.assignedStaff =
        this.staff.find((s) => s.id === row.assignedStaffId) ?? null;
    }
    if (include?.events) {
      out.events = this.events
        .filter((e) => e.reportId === row.id)
        .sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime());
    }
    return out;
  }

  report = {
    create: jest.fn(async ({ data }: any) => {
      const { events, ...rest } = data;
      const now = new Date(Date.UTC(2026, 9, 20, 10, 0, this.reportSeq));
      const row = {
        id: `rep_${++this.reportSeq}`,
        code: `PULSE-${1042 + this.reportSeq}`,
        category: null,
        location: null,
        imageUrl: null,
        priority: 'MEDIUM',
        status: 'SUBMITTED',
        assignedDepartment: null,
        assignedStaffId: null,
        assignedAt: null,
        resolutionNotes: null,
        rejectionReason: null,
        aiCategory: null,
        aiPriority: null,
        aiConfidence: null,
        aiDepartment: null,
        aiReasons: null,
        aiOverrideBy: null,
        aiOverrideAt: null,
        createdAt: now,
        updatedAt: now,
        resolvedAt: null,
        ...rest,
      };
      this.reports.push(row);
      if (events?.create) {
        this.events.push({
          id: `evt_${++this.eventSeq}`,
          reportId: row.id,
          type: events.create.type,
          actorId: events.create.actorId,
          actorRole: events.create.actorRole,
          remark: events.create.remark ?? null,
          createdAt: now,
        });
      }
      return row;
    }),
    count: jest.fn(async () => this.reports.length),
    findMany: jest.fn(async ({ where, orderBy }: any) => {
      let rows = this.reports.filter((row) => this.matches(row, where));
      if (orderBy?.createdAt === 'desc') {
        rows = [...rows].sort(
          (a, b) => b.createdAt.getTime() - a.createdAt.getTime(),
        );
      }
      return rows;
    }),
    findFirst: jest.fn(async ({ where, include }: any) => {
      const row =
        this.reports.find((candidate) => this.matches(candidate, where)) ??
        null;
      return this.withRelations(row, include);
    }),
    findUnique: jest.fn(async ({ where, include }: any) => {
      const row =
        this.reports.find((candidate) => this.matches(candidate, where)) ??
        null;
      return this.withRelations(row, include);
    }),
    update: jest.fn(async ({ where, data }: any) => {
      const row = this.reports.find((candidate) =>
        this.matches(candidate, where),
      );
      if (!row) throw new Error('Record not found');
      Object.assign(row, data, { updatedAt: new Date() });
      return row;
    }),
    updateMany: jest.fn(async ({ where, data }: any) => {
      const rows = this.reports.filter((row) => this.matches(row, where));
      for (const row of rows) {
        Object.assign(row, data, { updatedAt: new Date() });
      }
      return { count: rows.length };
    }),
    delete: jest.fn(async ({ where }: any) => {
      const index = this.reports.findIndex((row) =>
        this.matches(row, where),
      );
      if (index < 0) throw new Error('Record not found');
      const [removed] = this.reports.splice(index, 1);
      this.events = this.events.filter((e) => e.reportId !== removed.id);
      return removed;
    }),
  };

  reportEvent = {
    create: jest.fn(async ({ data }: any) => {
      const event = {
        id: `evt_${++this.eventSeq}`,
        remark: null,
        createdAt: new Date(),
        ...data,
      };
      this.events.push(event);
      return event;
    }),
  };

  staffUser = {
    findUnique: jest.fn(async ({ where }: any) => {
      return this.staff.find((row) => this.matches(row, where)) ?? null;
    }),
  };

  attachment = {
    findFirst: jest.fn(async ({ where }: any) => {
      return (
        this.attachments.find((row) => this.matches(row, where)) ?? null
      );
    }),
  };

  $transaction = async <T>(fn: (tx: FakePrisma) => Promise<T>): Promise<T> => {
    return fn(this);
  };
}

const baseDto = (over: Partial<CreateReportDto> = {}): CreateReportDto => ({
  title: 'Water Leakage',
  description: 'Water leaking near the electrical panel on the second floor.',
  location: 'Block B · 2nd Floor',
  category: 'Infrastructure',
  ...over,
});

describe('ReportsService issue handling workflow', () => {
  let prisma: FakePrisma;
  let attachments: { claimForReport: jest.Mock; downloadForReport: jest.Mock };
  let realtime: { publishReportChanged: jest.Mock };
  let service: ReportsService;

  beforeEach(() => {
    prisma = new FakePrisma();
    attachments = {
      claimForReport: jest.fn(async () => true),
      downloadForReport: jest.fn(async () => ({
        buffer: Buffer.from('photo-bytes'),
        contentType: 'image/png',
      })),
    };
    realtime = { publishReportChanged: jest.fn() };
    service = new ReportsService(
      prisma as any,
      attachments as any,
      realtime as any,
    );
  });

  const createReport = async (studentId = '4301') =>
    (await service.createReport(studentId, baseDto())).id;

  it('lets an admin assign a submitted report to an active STAFF account', async () => {
    const id = await createReport();

    const detail = await service.assignReport(ADMIN, id, {
      staffId: STAFF_A.staffId,
      department: 'Maintenance',
    });

    expect(detail.status).toBe('ASSIGNED');
    expect(detail.assignedStaff?.id).toBe(STAFF_A.staffId);
    expect((detail.assignedStaff as any)?.passwordHash).toBeUndefined();
    expect(detail.assignedAt).toBeInstanceOf(Date);
    expect(detail.assignedDepartment).toBe('Maintenance');
    expect(prisma.events.map((e) => e.type)).toEqual(['SUBMITTED', 'ASSIGNED']);
    expect(prisma.events[1]).toMatchObject({
      actorId: ADMIN.staffId,
      actorRole: 'ADMIN',
      remark: 'Maintenance',
    });
    expect(realtime.publishReportChanged).toHaveBeenCalledWith({
      reportId: id,
      code: detail.code,
      status: 'ASSIGNED',
      change: 'assigned',
      studentId: '4301',
      assignedStaffId: STAFF_A.staffId,
      previousAssignedStaffId: null,
    });
  });

  it('refuses inactive, admin, or unknown assignees', async () => {
    const id = await createReport();
    realtime.publishReportChanged.mockClear();

    await expect(
      service.assignReport(ADMIN, id, { staffId: 'staff_inactive' }),
    ).rejects.toThrow(BadRequestException);
    await expect(
      service.assignReport(ADMIN, id, { staffId: 'admin_1' }),
    ).rejects.toThrow(BadRequestException);
    await expect(
      service.assignReport(ADMIN, id, { staffId: 'missing' }),
    ).rejects.toThrow(BadRequestException);
    expect(realtime.publishReportChanged).not.toHaveBeenCalled();
  });

  it('reassigns an in-progress report without regressing its status', async () => {
    const id = await createReport();
    await service.assignReport(ADMIN, id, { staffId: STAFF_A.staffId });
    await service.acceptReport(STAFF_A as any, id);

    const detail = await service.assignReport(ADMIN, id, {
      staffId: STAFF_B.staffId,
    });

    expect(detail.status).toBe('IN_PROGRESS');
    expect(detail.assignedStaff?.id).toBe(STAFF_B.staffId);
    expect(prisma.events.map((e) => e.type)).toEqual([
      'SUBMITTED',
      'ASSIGNED',
      'IN_PROGRESS',
      'REASSIGNED',
    ]);
    expect(realtime.publishReportChanged).toHaveBeenLastCalledWith({
      reportId: id,
      code: detail.code,
      status: 'IN_PROGRESS',
      change: 'reassigned',
      studentId: '4301',
      assignedStaffId: STAFF_B.staffId,
      previousAssignedStaffId: STAFF_A.staffId,
    });
  });

  it('rejects assignment from a non-admin actor', async () => {
    const id = await createReport();
    await expect(
      service.assignReport(STAFF_A as any, id, { staffId: STAFF_B.staffId }),
    ).rejects.toThrow(ForbiddenException);
  });

  it('accepts only the assigned staff member’s own report', async () => {
    const id = await createReport();
    await service.assignReport(ADMIN, id, { staffId: STAFF_A.staffId });

    await expect(
      service.acceptReport(STAFF_B as any, id),
    ).rejects.toThrow(NotFoundException);
    await expect(
      service.acceptReport(ADMIN as any, id),
    ).rejects.toThrow(ForbiddenException);

    const accepted = await service.acceptReport(STAFF_A as any, id);
    expect(accepted.status).toBe('IN_PROGRESS');
    expect(prisma.events.map((e) => e.type)).toEqual([
      'SUBMITTED',
      'ASSIGNED',
      'IN_PROGRESS',
    ]);
    expect(realtime.publishReportChanged).toHaveBeenLastCalledWith({
      reportId: id,
      code: accepted.code,
      status: 'IN_PROGRESS',
      change: 'accepted',
      studentId: '4301',
      assignedStaffId: STAFF_A.staffId,
    });

    await expect(
      service.acceptReport(STAFF_A as any, id),
    ).rejects.toThrow(ConflictException);
  });

  it('allows progress notes only on the assignee’s active report', async () => {
    const id = await createReport();
    await service.assignReport(ADMIN, id, { staffId: STAFF_A.staffId });

    await expect(
      service.addProgressNote(STAFF_B as any, id, { note: 'Not mine' }),
    ).rejects.toThrow(NotFoundException);

    const noted = await service.addProgressNote(STAFF_A as any, id, {
      note: 'Parts ordered; repair scheduled.',
    });
    expect(noted.events.at(-1)).toMatchObject({
      type: 'PROGRESS_NOTE',
      actorRole: 'STAFF',
      remark: 'Parts ordered; repair scheduled.',
    });
    expect(realtime.publishReportChanged).toHaveBeenLastCalledWith({
      reportId: id,
      code: noted.code,
      status: 'ASSIGNED',
      change: 'progress',
      studentId: '4301',
      assignedStaffId: STAFF_A.staffId,
      notifyStudent: false,
    });

    await expect(
      service.addProgressNote(STAFF_A as any, id, { note: '   ' }),
    ).rejects.toThrow(BadRequestException);
  });

  it('requires IN_PROGRESS and non-empty notes to resolve', async () => {
    const id = await createReport();
    await service.assignReport(ADMIN, id, { staffId: STAFF_A.staffId });

    await expect(
      service.resolveReport(STAFF_A as any, id, {
        resolutionNotes: 'Fixed.',
      }),
    ).rejects.toThrow(ConflictException);

    await service.acceptReport(STAFF_A as any, id);
    await expect(
      service.resolveReport(STAFF_A as any, id, {
        resolutionNotes: '   ',
      }),
    ).rejects.toThrow(BadRequestException);

    const resolved = await service.resolveReport(STAFF_A as any, id, {
      resolutionNotes: 'Replaced the faulty valve and verified no leakage.',
    });
    expect(resolved.status).toBe('RESOLVED');
    expect(resolved.resolvedAt).toBeInstanceOf(Date);
    expect(resolved.resolutionNotes).toBe(
      'Replaced the faulty valve and verified no leakage.',
    );
    expect(resolved.events.at(-1)).toMatchObject({
      type: 'RESOLVED',
      actorRole: 'STAFF',
      remark: 'Replaced the faulty valve and verified no leakage.',
    });
    expect(realtime.publishReportChanged).toHaveBeenLastCalledWith({
      reportId: id,
      code: resolved.code,
      status: 'RESOLVED',
      change: 'resolved',
      studentId: '4301',
      assignedStaffId: STAFF_A.staffId,
    });
  });

  it('allows only an admin to reject with a recorded reason', async () => {
    const id = await createReport();

    await expect(
      service.rejectReport(STAFF_A as any, id, { reason: 'Not valid.' }),
    ).rejects.toThrow(ForbiddenException);
    await expect(
      service.rejectReport(ADMIN, id, { reason: '   ' }),
    ).rejects.toThrow(BadRequestException);

    const rejected = await service.rejectReport(ADMIN, id, {
      reason: 'Duplicate report; already fixed under another ticket.',
    });
    expect(rejected.status).toBe('REJECTED');
    expect(rejected.rejectionReason).toBe(
      'Duplicate report; already fixed under another ticket.',
    );
    expect(rejected.events.at(-1)).toMatchObject({
      type: 'REJECTED',
      actorRole: 'ADMIN',
    });
    expect(realtime.publishReportChanged).toHaveBeenLastCalledWith({
      reportId: id,
      code: rejected.code,
      status: 'REJECTED',
      change: 'rejected',
      studentId: '4301',
      assignedStaffId: null,
    });

    await expect(
      service.rejectReport(ADMIN, id, { reason: 'Again' }),
    ).rejects.toThrow(ConflictException);
  });

  it('lists only assigned reports for STAFF and every report for ADMIN', async () => {
    const mine = await createReport('4301');
    const other = await createReport('9999');
    await service.assignReport(ADMIN, mine, { staffId: STAFF_A.staffId });

    const staffAReports = await service.listReportsForStaff(
      STAFF_A as any,
    );
    expect(staffAReports.map((r) => r.id)).toEqual([mine]);
    expect(await service.listReportsForStaff(STAFF_B as any)).toEqual([]);

    const adminReports = await service.listReportsForStaff(ADMIN as any);
    expect(adminReports.map((r) => r.id).sort()).toEqual(
      [mine, other].sort(),
    );
  });

  it('hides internal notes and staff identity from the student timeline', async () => {
    const id = await createReport('4301');
    await service.assignReport(ADMIN, id, { staffId: STAFF_A.staffId });
    await service.acceptReport(STAFF_A as any, id);
    await service.addProgressNote(STAFF_A as any, id, {
      note: 'Internal access code changed.',
    });
    await service.resolveReport(STAFF_A as any, id, {
      resolutionNotes: 'Repaired and tested.',
    });

    const studentView = await service.getOwnedReport('4301', id);
    expect(studentView.events.map((e) => e.type)).toEqual([
      'SUBMITTED',
      'ASSIGNED',
      'IN_PROGRESS',
      'RESOLVED',
    ]);
    expect(studentView.events.some((e) => e.type === 'PROGRESS_NOTE')).toBe(
      false,
    );
    expect('assignedStaff' in studentView).toBe(false);
    expect(studentView.resolutionNotes).toBe('Repaired and tested.');

    const staffView = await service.getReportForStaff(
      STAFF_A as any,
      id,
    );
    expect(staffView.events.map((e) => e.type)).toContain('PROGRESS_NOTE');
    expect(staffView.assignedStaff?.id).toBe(STAFF_A.staffId);

    await expect(
      service.getOwnedReport('9999', id),
    ).rejects.toThrow(NotFoundException);
    await expect(
      service.getReportForStaff(STAFF_B as any, id),
    ).rejects.toThrow(NotFoundException);
    await expect(
      service.getReportForStaff(ADMIN as any, id),
    ).resolves.toBeDefined();
  });

  it('guards staff photo access behind assignment while allowing admins', async () => {
    const id = await createReport();
    await service.assignReport(ADMIN, id, { staffId: STAFF_A.staffId });

    await expect(
      service.downloadReportPhoto(STAFF_B as any, id),
    ).rejects.toThrow(NotFoundException);
    await expect(
      service.downloadReportPhoto(ADMIN as any, id),
    ).resolves.toMatchObject({ contentType: 'image/png' });
    await expect(
      service.downloadReportPhoto(STAFF_A as any, id),
    ).resolves.toMatchObject({ contentType: 'image/png' });
    expect(attachments.downloadForReport).toHaveBeenCalledWith(id);
  });
});
