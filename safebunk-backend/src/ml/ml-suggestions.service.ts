import {
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { AuthenticatedStaff } from '../common/decorators/current-user.decorator';
import { MlClientService, MlServiceError } from './ml-client.service';
import {
  DEFAULT_MAX_DUPLICATE_CANDIDATES,
  MAX_EXISTING_COMPLAINTS,
  SUPPORTED_REPORT_CATEGORY_SET,
} from './ml.constants';
import {
  CategorySuggestionView,
  DraftDuplicateInput,
  DuplicateCandidateView,
  DuplicateSuggestionView,
  ExistingComplaintInput,
  MlFailureReason,
  NewComplaintInput,
} from './ml.types';

const DUPLICATE_SCORE_NOTE =
  'Cosine similarity plus a small category/location support boost. ' +
  'This is a ranking score, not a calibrated probability.';

const FALLBACK_MESSAGE =
  'ML suggestions are temporarily unavailable. No report data was changed.';

const SOURCE_REPORT_SELECT = {
  id: true,
  code: true,
  title: true,
  description: true,
  category: true,
  location: true,
  assignedStaffId: true,
} as const;

const CANDIDATE_REPORT_SELECT = {
  id: true,
  code: true,
  title: true,
  description: true,
  category: true,
  location: true,
  status: true,
} as const;

const STAFF_VISIBLE_STATUSES = ['ASSIGNED', 'IN_PROGRESS', 'RESOLVED'] as const;

type SourceReport = Prisma.ReportGetPayload<{ select: typeof SOURCE_REPORT_SELECT }>;
type CandidateReport = Prisma.ReportGetPayload<{
  select: typeof CANDIDATE_REPORT_SELECT;
}>;

function mlCategory(value: string | null): string | null {
  if (!value) return null;
  const normalized = value.trim();
  return SUPPORTED_REPORT_CATEGORY_SET.has(normalized) ? normalized : null;
}

function mlLocation(value: string | null): string | null {
  if (!value) return null;
  const normalized = value.trim().replace(/\s+/g, ' ');
  return normalized || null;
}

function toComplaint(report: SourceReport | CandidateReport): ExistingComplaintInput {
  return {
    complaintId: report.id,
    description: report.description.trim(),
    category: mlCategory(report.category),
    location: mlLocation(report.location),
  };
}

@Injectable()
export class MlSuggestionsService {
  private readonly logger = new Logger(MlSuggestionsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly client: MlClientService,
  ) {}

  async suggestCategory(description: string): Promise<CategorySuggestionView> {
    try {
      const prediction = await this.client.predictCategory(description.trim());
      return {
        available: true,
        suggestionOnly: true,
        reason: null,
        message: prediction.manualReviewRecommended
          ? 'Low-confidence category suggestion; human review is recommended.'
          : 'Category suggestion only; no report fields were changed.',
        category: prediction.category,
        confidence: prediction.confidence,
        modelVersion: prediction.modelVersion,
        manualReviewRecommended: prediction.manualReviewRecommended,
        decision: prediction.decision,
        threshold: prediction.threshold,
      };
    } catch (error) {
      if (!(error instanceof MlServiceError)) throw error;
      this.logger.warn(`Category suggestion unavailable: ${error.reason}`);
      return {
        available: false,
        suggestionOnly: true,
        reason: error.reason,
        message: FALLBACK_MESSAGE,
        category: null,
        confidence: null,
        modelVersion: null,
        manualReviewRecommended: true,
        decision: 'unavailable',
        threshold: null,
      };
    }
  }

  /**
   * Student duplicate suggestions are scoped to reports the authenticated
   * student owns. The source report must be owned by that student, and only
   * that student's other reports are sent to the ML service.
   */
  async suggestDuplicatesForStudent(
    studentId: string,
    reportId: string,
    maxCandidates = DEFAULT_MAX_DUPLICATE_CANDIDATES,
  ): Promise<DuplicateSuggestionView> {
    const source = await this.prisma.report.findFirst({
      where: { id: reportId, studentId },
      select: SOURCE_REPORT_SELECT,
    });
    if (!source) {
      throw new NotFoundException('Report not found');
    }

    const candidates = await this.prisma.report.findMany({
      where: { studentId, id: { not: reportId } },
      orderBy: { createdAt: 'desc' },
      take: MAX_EXISTING_COMPLAINTS,
      select: CANDIDATE_REPORT_SELECT,
    });

    return this.detect(
      {
        description: source.description.trim(),
        category: mlCategory(source.category),
        location: mlLocation(source.location),
      },
      candidates,
      reportId,
      maxCandidates,
    );
  }

  /**
   * Pre-submission duplicate check for an unsaved draft. It uses the same
   * detector and ownership scope as the report-id route, but there is no source
   * report id yet and no report is created or modified.
   */
  async suggestDuplicatesForDraft(
    studentId: string,
    input: DraftDuplicateInput,
  ): Promise<DuplicateSuggestionView> {
    const candidates = await this.prisma.report.findMany({
      where: { studentId },
      orderBy: { createdAt: 'desc' },
      take: MAX_EXISTING_COMPLAINTS,
      select: CANDIDATE_REPORT_SELECT,
    });

    return this.detect(
      {
        description: input.description.trim(),
        category: mlCategory(input.category),
        location: mlLocation(input.location),
      },
      candidates,
      null,
      input.maxCandidates,
    );
  }

  /**
   * Staff duplicate suggestions follow the existing report visibility rules:
   * STAFF can only use reports assigned to them; ADMIN can use all reports.
   */
  async suggestDuplicatesForStaff(
    actor: AuthenticatedStaff,
    reportId: string,
    maxCandidates = DEFAULT_MAX_DUPLICATE_CANDIDATES,
  ): Promise<DuplicateSuggestionView> {
    if (actor.role !== 'STAFF' && actor.role !== 'ADMIN') {
      throw new ForbiddenException('Staff access is required.');
    }

    const source = await this.prisma.report.findUnique({
      where: { id: reportId },
      select: SOURCE_REPORT_SELECT,
    });
    if (!source) {
      throw new NotFoundException('Report not found');
    }
    if (actor.role === 'STAFF' && source.assignedStaffId !== actor.staffId) {
      throw new NotFoundException('Report not found');
    }

    const where: Prisma.ReportWhereInput = { id: { not: reportId } };
    if (actor.role === 'STAFF') {
      where.assignedStaffId = actor.staffId;
      where.status = { in: [...STAFF_VISIBLE_STATUSES] };
    }

    const candidates = await this.prisma.report.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: MAX_EXISTING_COMPLAINTS,
      select: CANDIDATE_REPORT_SELECT,
    });

    return this.detect(
      {
        description: source.description.trim(),
        category: mlCategory(source.category),
        location: mlLocation(source.location),
      },
      candidates,
      reportId,
      maxCandidates,
    );
  }

  private async detect(
    newComplaint: NewComplaintInput,
    candidates: CandidateReport[],
    reportId: string | null,
    maxCandidates: number,
  ): Promise<DuplicateSuggestionView> {
    try {
      const result = await this.client.detectDuplicates({
        newComplaint,
        existingComplaints: candidates.map(toComplaint),
        maxCandidates,
      });

      const candidateById = new Map(
        candidates.map((candidate) => [candidate.id, candidate]),
      );
      const seen = new Set<string>();
      const views: DuplicateCandidateView[] = [];
      for (const score of result.candidates) {
        const report = candidateById.get(score.complaintId);
        if (!report || seen.has(report.id)) continue;
        seen.add(report.id);
        views.push({
          reportId: report.id,
          reportCode: report.code,
          title: report.title,
          status: report.status,
          category: report.category,
          location: report.location,
          similarityScore: score.similarityScore,
          rankingScore: score.rankingScore,
          categoryMatch: score.categoryMatch,
          locationMatch: score.locationMatch,
          reasons: score.reasons,
        });
      }

      return {
        available: true,
        suggestionOnly: true,
        action: 'suggestion_only',
        reason: null,
        reportId,
        decision: result.decision,
        candidates: views,
        duplicateThreshold: result.duplicateThreshold,
        uncertainThreshold: result.uncertainThreshold,
        similarityMetric: result.similarityMetric,
        rankingMetric: result.rankingMetric,
        modelVersion: result.modelVersion,
        scoreNote: result.scoreNote,
        manualReviewRecommended: result.manualReviewRecommended,
        existingComplaintsEvaluated: result.existingComplaintsEvaluated,
        message: result.message,
      };
    } catch (error) {
      if (!(error instanceof MlServiceError)) throw error;
      this.logger.warn(`Duplicate suggestions unavailable: ${error.reason}`);
      return this.unavailableDuplicates(reportId, error.reason);
    }
  }

  private unavailableDuplicates(
    reportId: string | null,
    reason: MlFailureReason,
  ): DuplicateSuggestionView {
    return {
      available: false,
      suggestionOnly: true,
      action: 'suggestion_only',
      reason,
      reportId,
      decision: null,
      candidates: [],
      duplicateThreshold: null,
      uncertainThreshold: null,
      similarityMetric: null,
      rankingMetric: null,
      modelVersion: null,
      scoreNote: DUPLICATE_SCORE_NOTE,
      manualReviewRecommended: true,
      existingComplaintsEvaluated: null,
      message: FALLBACK_MESSAGE,
    };
  }
}
