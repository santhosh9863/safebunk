import { BadRequestException, Injectable, NotFoundException, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateReportDto } from './dto/create-report.dto';
import { Report } from '@prisma/client';
import { isReportPriority } from './report-status';
import { AttachmentsService } from './attachments/attachments.service';

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
  aiCategory: string | null;
  aiPriority: string | null;
  aiConfidence: number | null;
  createdAt: Date;
  updatedAt: Date;
  resolvedAt: Date | null;
}

@Injectable()
export class ReportsService {
  private readonly logger = new Logger(ReportsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly attachments: AttachmentsService,
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
    const priority = dto.priority && isReportPriority(dto.priority) ? dto.priority : 'MEDIUM';
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
        await this.prisma.report.delete({ where: { id: report.id } }).catch(() => undefined);
        throw error;
      }
    }

    return report;
  }

  /** Own reports only, newest first. */
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
   */
  async getOwnedReport(studentId: string, id: string): Promise<ReportSummary> {
    const report = await this.prisma.report.findFirst({
      where: { id, studentId },
    });
    if (!report) {
      throw new NotFoundException('Report not found');
    }
    return this.toSummary(report);
  }

  /**
   * Staff/admin view: all reports, newest first. This is intentionally
   * separate from listMyReports; ownership is a student-side rule.
   */
  async listReportsForStaff(): Promise<ReportSummary[]> {
    const rows = await this.prisma.report.findMany({
      orderBy: { createdAt: 'desc' },
    });
    return rows.map((r) => this.toSummary(r));
  }

  /** Staff/admin view of any report, including reports owned by students. */
  async getReportForStaff(id: string): Promise<ReportSummary> {
    const report = await this.prisma.report.findUnique({
      where: { id },
    });
    if (!report) {
      throw new NotFoundException('Report not found');
    }
    return this.toSummary(report);
  }

  private async nextCode(): Promise<string> {
    const count = await this.prisma.report.count();
    // Monotonic per DB; unique constraint backstops any race.
    return `PULSE-${1042 + count}`;
  }

  private toSummary(r: Report): ReportSummary {
    return {
      id: r.id,
      code: r.code,
      title: r.title,
      description: r.description,
      category: r.category,
      location: r.location,
      imageUrl: r.imageUrl,
      priority: r.priority,
      status: r.status,
      assignedDepartment: r.assignedDepartment,
      aiCategory: r.aiCategory,
      aiPriority: r.aiPriority,
      aiConfidence: r.aiConfidence,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      resolvedAt: r.resolvedAt,
    };
  }
}
