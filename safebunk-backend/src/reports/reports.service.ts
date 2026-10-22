import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma, Report, ReportEvent, StaffUser } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { AuthenticatedStaff } from '../common/decorators/current-user.decorator';
import { CreateReportDto } from './dto/create-report.dto';
import {
  AddProgressNoteDto,
  AssignReportDto,
  RejectReportDto,
  ResolveReportDto,
} from './dto/staff-report-actions.dto';
import {
  canTransition,
  isReportPriority,
  isReportStatus,
  REJECTABLE_STATUSES,
  ReportStatus,
} from './report-status';
import { AttachmentsService } from './attachments/attachments.service';
import {
  ReportChangeType,
  ReportsRealtimeGateway,
} from './reports-realtime.gateway';

type StaffAssignee = Pick<
  StaffUser,
  'id' | 'username' | 'displayName' | 'role' | 'active'
>;

type ReportSummarySource = Report & {
  assignedStaff?: StaffAssignee | null;
};

type ReportDetailSource = Report & {
  assignedStaff?: StaffAssignee | null;
  events: ReportEvent[];
};

export interface ReportEventView {
  id: string;
  type: string;
  actorRole: string;
  remark: string | null;
  createdAt: Date;
}

export interface ReportSummary {
  id: string;
  code: string;
  title: string;
  description: string;
  category: string | null;
  location: string | null;
  imageUrl: string | null;
  priority: string;
  status: string;
  assignedDepartment: string | null;
  assignedAt: Date | null;
  assignedStaff?: StaffAssignee;
  resolutionNotes: string | null;
  rejectionReason: string | null;
  aiCategory: string | null;
  aiPriority: string | null;
  aiConfidence: number | null;
  createdAt: Date;
  updatedAt: Date;
  resolvedAt: Date | null;
}

export interface ReportDetail extends ReportSummary {
  events: ReportEventView[];
}

const STAFF_VISIBLE_STATUSES: readonly ReportStatus[] = [
  'ASSIGNED',
  'IN_PROGRESS',
  'RESOLVED',
];

const STUDENT_VISIBLE_EVENT_TYPES = new Set([
  'SUBMITTED',
  'ASSIGNED',
  'REASSIGNED',
  'IN_PROGRESS',
  'RESOLVED',
  'REJECTED',
]);

@Injectable()
export class ReportsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly attachments: AttachmentsService,
    private readonly realtime: ReportsRealtimeGateway,
  ) {}

  /**
   * Rules-based routing stub. NOT machine learning: no model, no training,
   * no prediction. Returns null until a real rules table (Phase 7) exists.
   * Kept as a single seam so ML can replace it without touching callers.
   */
  private recommendDepartment(_dto: CreateReportDto): {
    assignedDepartment: string | null;
    aiDepartment: string | null;
    aiConfidence: number | null;
    aiReasons: string | null;
  } {
    return {
      assignedDepartment: null,
      aiDepartment: null,
      aiConfidence: null,
      aiReasons: null,
    };
  }

  /**
   * Creates a report for the authenticated student.
   * `studentId` is ALWAYS taken from the AuthGuard session — never from the
   * request body (CreateReportDto has no studentId field; whitelist validation
   * rejects it if a client tries to send one).
   */
  async createReport(studentId: string, dto: CreateReportDto): Promise<Report> {
    // Reject an attachment that does not exist, belongs to another student, or
    // is already claimed — before creating anything.
    if (dto.attachmentId) {
      const attachment = await this.prisma.attachment.findFirst({
        where: { id: dto.attachmentId, studentId },
      });
      if (!attachment || attachment.reportId) {
        throw new BadRequestException('Invalid or already-used attachment.');
      }
    }

    const routing = this.recommendDepartment(dto);
    const priority =
      dto.priority && isReportPriority(dto.priority) ? dto.priority : 'MEDIUM';
    const code = await this.nextCode();

    const report = await this.prisma.report.create({
      data: {
        code,
        studentId,
        title: dto.title.trim(),
        description: dto.description.trim(),
        category: dto.category?.trim() || null,
        location: dto.location?.trim() || null,
        // imageUrl is derived server-side below, never taken from the client.
        imageUrl: null,
        priority,
        status: 'SUBMITTED',
        assignedDepartment: routing.assignedDepartment,
        aiDepartment: routing.aiDepartment,
        aiConfidence: routing.aiConfidence,
        aiReasons: routing.aiReasons,
        events: {
          create: {
            type: 'SUBMITTED',
            actorId: studentId,
            actorRole: 'STUDENT',
          },
        },
      },
    });

    if (dto.attachmentId) {
      try {
        const claimed = await this.attachments.claimForReport(
          studentId,
          dto.attachmentId,
          report.id,
        );
        if (!claimed) {
          throw new BadRequestException('Invalid or already-used attachment.');
        }
        report.imageUrl = AttachmentsService.urlFor(dto.attachmentId);
        await this.prisma.report.update({
          where: { id: report.id },
          data: { imageUrl: report.imageUrl },
        });
      } catch (error) {
        // Lost a race, stale attachment, or the follow-up update failed: roll
        // back the just-created report so it never references a photo it does
        // not own and no attachment stays claimed by a half-created report.
        // The Attachment FK is `onDelete: SetNull`, which releases the claim.
        await this.prisma.report
          .delete({ where: { id: report.id } })
          .catch(() => undefined);
        throw error;
      }
    }

    this.publishReportChanged(report, 'created');
    return report;
  }

  /** Own reports only, newest first. Assignment identity is never exposed. */
  async listMyReports(studentId: string): Promise<ReportSummary[]> {
    const rows = await this.prisma.report.findMany({
      where: { studentId },
      orderBy: { createdAt: 'desc' },
    });
    return rows.map((r) => this.toSummary(r));
  }

  /**
   * Single report fetch. The query always filters by the authenticated
   * studentId, so another student's report is indistinguishable from a
   * missing one (404) — no IDOR, no existence oracle.
   *
   * Student history deliberately excludes internal progress notes and all
   * staff identity fields. Resolution/rejection reasons remain visible.
   */
  async getOwnedReport(studentId: string, id: string): Promise<ReportDetail> {
    const report = await this.prisma.report.findFirst({
      where: { id, studentId },
      include: {
        events: {
          orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
        },
      },
    });
    if (!report) {
      throw new NotFoundException('Report not found');
    }
    return this.toDetail(report, false);
  }

  /**
   * Staff/admin view: ADMIN sees all reports; STAFF sees only reports assigned
   * to the staffId from the verified session. The status filter is optional,
   * and STAFF can never widen their scope through it.
   */
  async listReportsForStaff(
    actor: AuthenticatedStaff,
    status?: string,
  ): Promise<ReportSummary[]> {
    this.assertStaffOrAdminActor(actor);
    const where: Prisma.ReportWhereInput = {};

    if (actor.role === 'STAFF') {
      where.assignedStaffId = actor.staffId;
      where.status = status
        ? STAFF_VISIBLE_STATUSES.includes(status as ReportStatus)
          ? (status as ReportStatus)
          : { in: [] }
        : { in: [...STAFF_VISIBLE_STATUSES] };
    } else if (status) {
      if (!isReportStatus(status)) {
        throw new BadRequestException('Invalid report status filter');
      }
      where.status = status;
    }

    const rows = await this.prisma.report.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      include: {
        assignedStaff: {
          select: {
            id: true,
            username: true,
            displayName: true,
            role: true,
            active: true,
          },
        },
      },
    });

    return rows.map((r) => this.toSummary(r, true));
  }

  /**
   * Staff/admin detail. A STAFF token may read only its own assignments; an
   * unassigned report is indistinguishable from a missing one (404).
   */
  async getReportForStaff(
    actor: AuthenticatedStaff,
    id: string,
  ): Promise<ReportDetail> {
    this.assertStaffOrAdminActor(actor);
    const report = await this.prisma.report.findUnique({
      where: { id },
      include: {
        assignedStaff: {
          select: {
            id: true,
            username: true,
            displayName: true,
            role: true,
            active: true,
          },
        },
        events: {
          orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
        },
      },
    });
    if (!report) {
      throw new NotFoundException('Report not found');
    }
    this.assertCanViewStaffReport(actor, report);
    return this.toDetail(report, true);
  }

  /**
   * ADMIN-only assignment/reassignment to an active STAFF account. Assigning
   * a SUBMITTED report moves it to ASSIGNED; reassignment preserves
   * IN_PROGRESS (the new assignee continues from the existing history).
   */
  async assignReport(
    actor: AuthenticatedStaff,
    id: string,
    dto: AssignReportDto,
  ): Promise<ReportDetail> {
    this.assertAdminActor(actor);

    const target = await this.prisma.staffUser.findUnique({
      where: { id: dto.staffId },
      select: { id: true, role: true, active: true },
    });
    if (!target || !target.active || target.role !== 'STAFF') {
      throw new BadRequestException(
        'Assignments require an active STAFF account.',
      );
    }

    const report = await this.prisma.report.findUnique({
      where: { id },
      select: {
        id: true,
        studentId: true,
        status: true,
        assignedStaffId: true,
        assignedDepartment: true,
      },
    });
    if (!report) {
      throw new NotFoundException('Report not found');
    }
    if (
      !isReportStatus(report.status) ||
      !['SUBMITTED', 'ASSIGNED', 'IN_PROGRESS'].includes(report.status)
    ) {
      throw new ConflictException(
        'Resolved or rejected reports cannot be assigned.',
      );
    }

    const isReassignment = report.assignedStaffId !== null;
    const nextStatus: ReportStatus =
      report.status === 'SUBMITTED' ? 'ASSIGNED' : report.status;
    const now = new Date();
    const department =
      dto.department === undefined
        ? report.assignedDepartment
        : dto.department.trim() || null;

    await this.prisma.$transaction(async (tx) => {
      const updated = await tx.report.updateMany({
        where: { id, status: report.status },
        data: {
          assignedStaffId: target.id,
          assignedAt: now,
          status: nextStatus,
          assignedDepartment: department,
        },
      });
      if (updated.count !== 1) {
        throw new ConflictException(
          'The report changed while it was being assigned. Refresh and try again.',
        );
      }

      await tx.reportEvent.create({
        data: {
          reportId: id,
          type: isReassignment ? 'REASSIGNED' : 'ASSIGNED',
          actorId: actor.staffId,
          actorRole: 'ADMIN',
          remark: department,
        },
      });
    });

    const detail = await this.getReportForStaff(actor, id);
    this.realtime.publishReportChanged({
      reportId: detail.id,
      code: detail.code,
      status: detail.status,
      change: isReassignment ? 'reassigned' : 'assigned',
      studentId: report.studentId,
      assignedStaffId: target.id,
      previousAssignedStaffId: report.assignedStaffId,
    });
    return detail;
  }

  /**
   * STAFF-only acceptance of their own assignment. Uses a conditional update
   * so concurrent requests cannot accept/resolve the same report twice.
   */
  async acceptReport(
    actor: AuthenticatedStaff,
    id: string,
  ): Promise<ReportDetail> {
    this.assertStaffActor(actor);

    const report = await this.requireStaffAssignedReport(actor, id);
    this.assertTransition(report.status, 'IN_PROGRESS');

    await this.prisma.$transaction(async (tx) => {
      const updated = await tx.report.updateMany({
        where: {
          id,
          status: 'ASSIGNED',
          assignedStaffId: actor.staffId,
        },
        data: { status: 'IN_PROGRESS' },
      });
      if (updated.count !== 1) {
        throw new ConflictException(
          'Only an assigned report can be accepted. Refresh and try again.',
        );
      }
      await tx.reportEvent.create({
        data: {
          reportId: id,
          type: 'IN_PROGRESS',
          actorId: actor.staffId,
          actorRole: 'STAFF',
        },
      });
    });

    const detail = await this.getReportForStaff(actor, id);
    this.realtime.publishReportChanged({
      reportId: detail.id,
      code: detail.code,
      status: detail.status,
      change: 'accepted',
      studentId: report.studentId,
      assignedStaffId: actor.staffId,
    });
    return detail;
  }

  /**
   * STAFF-only progress notes for their own assigned/in-progress report.
   * Notes are internal history and are hidden from the student timeline.
   */
  async addProgressNote(
    actor: AuthenticatedStaff,
    id: string,
    dto: AddProgressNoteDto,
  ): Promise<ReportDetail> {
    this.assertStaffActor(actor);
    const note = dto.note.trim();
    if (!note) {
      throw new BadRequestException('Progress note cannot be empty.');
    }

    const report = await this.requireStaffAssignedReport(actor, id);
    if (report.status !== 'ASSIGNED' && report.status !== 'IN_PROGRESS') {
      throw new ConflictException(
        'Progress notes can only be added to active assignments.',
      );
    }

    await this.prisma.reportEvent.create({
      data: {
        reportId: id,
        type: 'PROGRESS_NOTE',
        actorId: actor.staffId,
        actorRole: 'STAFF',
        remark: note,
      },
    });

    const detail = await this.getReportForStaff(actor, id);
    this.realtime.publishReportChanged({
      reportId: detail.id,
      code: detail.code,
      status: detail.status,
      change: 'progress',
      studentId: report.studentId,
      assignedStaffId: actor.staffId,
      // Progress notes are internal and deliberately hidden from students.
      notifyStudent: false,
    });
    return detail;
  }

  /**
   * STAFF-only resolution of their own IN_PROGRESS report. Resolution notes
   * are required and are exposed to the student.
   */
  async resolveReport(
    actor: AuthenticatedStaff,
    id: string,
    dto: ResolveReportDto,
  ): Promise<ReportDetail> {
    this.assertStaffActor(actor);
    const notes = dto.resolutionNotes.trim();
    if (!notes) {
      throw new BadRequestException('Resolution notes cannot be empty.');
    }

    const report = await this.requireStaffAssignedReport(actor, id);
    this.assertTransition(report.status, 'RESOLVED');

    const now = new Date();
    await this.prisma.$transaction(async (tx) => {
      const updated = await tx.report.updateMany({
        where: {
          id,
          status: 'IN_PROGRESS',
          assignedStaffId: actor.staffId,
        },
        data: {
          status: 'RESOLVED',
          resolvedAt: now,
          resolutionNotes: notes,
        },
      });
      if (updated.count !== 1) {
        throw new ConflictException(
          'Only an in-progress report can be resolved. Refresh and try again.',
        );
      }
      await tx.reportEvent.create({
        data: {
          reportId: id,
          type: 'RESOLVED',
          actorId: actor.staffId,
          actorRole: 'STAFF',
          remark: notes,
        },
      });
    });

    const detail = await this.getReportForStaff(actor, id);
    this.realtime.publishReportChanged({
      reportId: detail.id,
      code: detail.code,
      status: detail.status,
      change: 'resolved',
      studentId: report.studentId,
      assignedStaffId: actor.staffId,
    });
    return detail;
  }

  /**
   * ADMIN-only explicit rejection with a required reason. Any non-terminal
   * status can be rejected; the reason is visible to the owning student.
   */
  async rejectReport(
    actor: AuthenticatedStaff,
    id: string,
    dto: RejectReportDto,
  ): Promise<ReportDetail> {
    this.assertAdminActor(actor);
    const reason = dto.reason.trim();
    if (!reason) {
      throw new BadRequestException('A rejection reason is required.');
    }

    const report = await this.prisma.report.findUnique({
      where: { id },
      select: {
        id: true,
        studentId: true,
        status: true,
        assignedStaffId: true,
      },
    });
    if (!report) {
      throw new NotFoundException('Report not found');
    }
    if (
      !isReportStatus(report.status) ||
      !REJECTABLE_STATUSES.includes(report.status)
    ) {
      throw new ConflictException('This report can no longer be rejected.');
    }

    await this.prisma.$transaction(async (tx) => {
      const updated = await tx.report.updateMany({
        where: {
          id,
          status: { in: [...REJECTABLE_STATUSES] },
        },
        data: {
          status: 'REJECTED',
          rejectionReason: reason,
          resolvedAt: null,
        },
      });
      if (updated.count !== 1) {
        throw new ConflictException(
          'The report changed while it was being rejected. Refresh and try again.',
        );
      }
      await tx.reportEvent.create({
        data: {
          reportId: id,
          type: 'REJECTED',
          actorId: actor.staffId,
          actorRole: 'ADMIN',
          remark: reason,
        },
      });
    });

    const detail = await this.getReportForStaff(actor, id);
    this.realtime.publishReportChanged({
      reportId: detail.id,
      code: detail.code,
      status: detail.status,
      change: 'rejected',
      studentId: report.studentId,
      assignedStaffId: report.assignedStaffId,
    });
    return detail;
  }

  /**
   * Staff-side attachment download. Authorization is checked against the
   * report before the attachment bytes are fetched.
   */
  async downloadReportPhoto(
    actor: AuthenticatedStaff,
    id: string,
  ): Promise<{ buffer: Buffer; contentType: string }> {
    this.assertStaffOrAdminActor(actor);
    const report = await this.prisma.report.findUnique({
      where: { id },
      select: { id: true, assignedStaffId: true, imageUrl: true },
    });
    if (!report) {
      throw new NotFoundException('Report not found');
    }
    this.assertCanViewStaffReport(actor, {
      assignedStaffId: report.assignedStaffId,
    });
    return this.attachments.downloadForReport(report.id);
  }

  private publishReportChanged(
    report: Pick<Report, 'id' | 'code' | 'status' | 'studentId'>,
    change: ReportChangeType,
    extra: {
      assignedStaffId?: string | null;
      previousAssignedStaffId?: string | null;
      notifyStudent?: boolean;
    } = {},
  ): void {
    this.realtime.publishReportChanged({
      reportId: report.id,
      code: report.code,
      status: report.status,
      change,
      studentId: report.studentId,
      ...extra,
    });
  }

  private assertAdminActor(actor: AuthenticatedStaff): void {
    if (actor.role !== 'ADMIN') {
      throw new ForbiddenException('Administrator access is required.');
    }
  }

  private assertStaffActor(actor: AuthenticatedStaff): void {
    if (actor.role !== 'STAFF') {
      throw new ForbiddenException('Staff access is required.');
    }
  }

  private assertStaffOrAdminActor(actor: AuthenticatedStaff): void {
    if (actor.role !== 'STAFF' && actor.role !== 'ADMIN') {
      throw new ForbiddenException('Staff access is required.');
    }
  }

  private assertCanViewStaffReport(
    actor: AuthenticatedStaff,
    report: { assignedStaffId: string | null },
  ): void {
    if (actor.role === 'STAFF' && report.assignedStaffId !== actor.staffId) {
      // Hide unassigned/other-staff reports rather than confirming their id.
      throw new NotFoundException('Report not found');
    }
  }

  private async requireStaffAssignedReport(
    actor: AuthenticatedStaff,
    id: string,
  ): Promise<Report> {
    const report = await this.prisma.report.findUnique({ where: { id } });
    if (!report) {
      throw new NotFoundException('Report not found');
    }
    if (report.assignedStaffId !== actor.staffId) {
      throw new NotFoundException('Report not found');
    }
    return report;
  }

  private assertTransition(from: string, to: ReportStatus): void {
    if (!isReportStatus(from) || !canTransition(from, to)) {
      throw new ConflictException(`Cannot move report from ${from} to ${to}.`);
    }
  }

  private async nextCode(): Promise<string> {
    const count = await this.prisma.report.count();
    // Monotonic per DB; unique constraint backstops any race.
    return `PULSE-${1042 + count}`;
  }

  private toSummary(
    r: ReportSummarySource,
    staffView = false,
  ): ReportSummary {
    const summary: ReportSummary = {
      id: r.id,
      code: r.code,
      title: r.title,
      description: r.description,
      category: r.category,
      location: r.location,
      imageUrl: staffView && r.imageUrl
        ? `/api/staff/reports/${r.id}/photo`
        : r.imageUrl,
      priority: r.priority,
      status: r.status,
      assignedDepartment: r.assignedDepartment,
      assignedAt: r.assignedAt,
      resolutionNotes: r.resolutionNotes,
      rejectionReason: r.rejectionReason,
      aiCategory: r.aiCategory,
      aiPriority: r.aiPriority,
      aiConfidence: r.aiConfidence,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      resolvedAt: r.resolvedAt,
    };

    if (staffView && r.assignedStaff) {
      summary.assignedStaff = r.assignedStaff;
    }

    return summary;
  }

  private toDetail(
    r: ReportDetailSource,
    staffView: boolean,
  ): ReportDetail {
    const events = (r.events ?? [])
      .filter(
        (event) =>
          staffView || STUDENT_VISIBLE_EVENT_TYPES.has(event.type),
      )
      .map((event) => ({
        id: event.id,
        type: event.type,
        actorRole: event.actorRole,
        remark: event.remark,
        createdAt: event.createdAt,
      }));

    return {
      ...this.toSummary(r, staffView),
      events,
    };
  }
}
