import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { MlSuggestionsService } from './ml-suggestions.service';
import { MlServiceError } from './ml-client.service';
import { DuplicateDetectionResult } from './ml.types';

const source = {
  id: 'rep_src',
  code: 'PULSE-1042',
  title: 'Flickering library lights',
  description: 'The lights in the main library reading room keep flickering.',
  category: 'Electrical',
  location: 'Main Library',
  assignedStaffId: 'staff-1',
};

const candidate = {
  id: 'rep_2',
  code: 'PULSE-1043',
  title: 'Library lighting problem',
  description: 'The library reading room lights are flashing constantly.',
  category: 'Electrical',
  location: 'Main Library',
  status: 'SUBMITTED',
};

const customCategoryCandidate = {
  ...candidate,
  id: 'rep_3',
  code: 'PULSE-1044',
  title: 'Custom category report',
  category: 'VIP',
  status: 'ASSIGNED',
};

const duplicateResult: DuplicateDetectionResult = {
  decision: 'match',
  candidates: [
    {
      complaintId: 'rep_2',
      similarityScore: 0.72,
      rankingScore: 0.76,
      category: 'Electrical',
      location: 'Main Library',
      categoryMatch: true,
      locationMatch: true,
      reasons: ['similar description text', 'same category: Electrical'],
    },
    {
      complaintId: 'rep_3',
      similarityScore: 0.52,
      rankingScore: 0.52,
      category: null,
      location: 'Main Library',
      categoryMatch: false,
      locationMatch: true,
      reasons: ['similar description text', 'same location: Main Library'],
    },
    {
      complaintId: 'unknown_report',
      similarityScore: 0.51,
      rankingScore: 0.51,
      category: null,
      location: null,
      categoryMatch: false,
      locationMatch: false,
      reasons: ['similar description text'],
    },
  ],
  duplicateThreshold: 0.5,
  uncertainThreshold: 0.4,
  similarityMetric: 'tfidf_cosine_similarity',
  rankingMetric: 'cosine_similarity_with_metadata_support',
  modelVersion: '0.2.0',
  scoreNote: 'Ranking score, not a probability.',
  manualReviewRecommended: true,
  action: 'suggestion_only',
  existingComplaintsEvaluated: 2,
  message: 'Potential duplicates found; these are suggestions only.',
};

function makePrisma() {
  return {
    report: {
      findFirst: jest.fn(),
      findUnique: jest.fn(),
      findMany: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn(),
      delete: jest.fn(),
    },
  };
}

function makeClient() {
  return {
    predictCategory: jest.fn(),
    detectDuplicates: jest.fn(),
  };
}

describe('MlSuggestionsService', () => {
  let prisma: ReturnType<typeof makePrisma>;
  let client: ReturnType<typeof makeClient>;
  let service: MlSuggestionsService;

  beforeEach(() => {
    prisma = makePrisma();
    client = makeClient();
    service = new MlSuggestionsService(prisma as never, client as never);
  });

  describe('category suggestions', () => {
    it('returns the model version, score, decision, and uncertain signal', async () => {
      client.predictCategory.mockResolvedValue({
        category: 'Electrical',
        confidence: 0.81,
        modelVersion: '0.1.0',
        manualReviewRecommended: false,
        decision: 'predict',
        threshold: 0.2,
      });

      const view = await service.suggestCategory('Library lights are flickering.');

      expect(view).toEqual({
        available: true,
        suggestionOnly: true,
        reason: null,
        message: 'Category suggestion only; no report fields were changed.',
        category: 'Electrical',
        confidence: 0.81,
        modelVersion: '0.1.0',
        manualReviewRecommended: false,
        decision: 'predict',
        threshold: 0.2,
      });
      expect(client.predictCategory).toHaveBeenCalledWith(
        'Library lights are flickering.',
      );
    });

    it('marks an abstain result for human review', async () => {
      client.predictCategory.mockResolvedValue({
        category: 'Other',
        confidence: 0.11,
        modelVersion: '0.1.0',
        manualReviewRecommended: true,
        decision: 'abstain',
        threshold: 0.2,
      });

      const view = await service.suggestCategory('Something is wrong somewhere.');

      expect(view.decision).toBe('abstain');
      expect(view.manualReviewRecommended).toBe(true);
      expect(view.message).toContain('human review');
    });

    it('returns a safe unavailable response instead of throwing', async () => {
      client.predictCategory.mockRejectedValue(
        new MlServiceError('ml_timeout', 'timed out'),
      );

      const view = await service.suggestCategory('Library lights are flickering.');

      expect(view.available).toBe(false);
      expect(view.reason).toBe('ml_timeout');
      expect(view.decision).toBe('unavailable');
      expect(view.category).toBeNull();
      expect(view.modelVersion).toBeNull();
      expect(view.message).toContain('No report data was changed');
    });
  });

  describe('student duplicate suggestions', () => {
    it('checks ownership, scopes candidates to the student, and maps scores', async () => {
      prisma.report.findFirst.mockResolvedValue(source);
      prisma.report.findMany.mockResolvedValue([candidate, customCategoryCandidate]);
      client.detectDuplicates.mockResolvedValue(duplicateResult);

      const view = await service.suggestDuplicatesForStudent(
        '4301',
        'rep_src',
        5,
      );

      expect(prisma.report.findFirst).toHaveBeenCalledWith({
        where: { id: 'rep_src', studentId: '4301' },
        select: expect.any(Object),
      });
      expect(prisma.report.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { studentId: '4301', id: { not: 'rep_src' } },
          take: 500,
        }),
      );
      expect(client.detectDuplicates).toHaveBeenCalledWith({
        newComplaint: {
          description: source.description,
          category: 'Electrical',
          location: 'Main Library',
        },
        existingComplaints: [
          {
            complaintId: 'rep_2',
            description: candidate.description,
            category: 'Electrical',
            location: 'Main Library',
          },
          {
            complaintId: 'rep_3',
            description: customCategoryCandidate.description,
            category: null,
            location: 'Main Library',
          },
        ],
        maxCandidates: 5,
      });

      expect(view.available).toBe(true);
      expect(view.modelVersion).toBe('0.2.0');
      expect(view.decision).toBe('match');
      expect(view.manualReviewRecommended).toBe(true);
      expect(view.candidates.map((item) => item.reportId)).toEqual([
        'rep_2',
        'rep_3',
      ]);
      expect(view.candidates[0]).toEqual({
        reportId: 'rep_2',
        reportCode: 'PULSE-1043',
        title: 'Library lighting problem',
        status: 'SUBMITTED',
        category: 'Electrical',
        location: 'Main Library',
        similarityScore: 0.72,
        rankingScore: 0.76,
        categoryMatch: true,
        locationMatch: true,
        reasons: ['similar description text', 'same category: Electrical'],
      });
      expect(prisma.report.create).not.toHaveBeenCalled();
      expect(prisma.report.update).not.toHaveBeenCalled();
      expect(prisma.report.updateMany).not.toHaveBeenCalled();
      expect(prisma.report.delete).not.toHaveBeenCalled();
    });

    it("hides another student's report behind a 404", async () => {
      prisma.report.findFirst.mockResolvedValue(null);

      await expect(
        service.suggestDuplicatesForStudent('4301', 'rep_other'),
      ).rejects.toThrow(NotFoundException);
      expect(prisma.report.findMany).not.toHaveBeenCalled();
      expect(client.detectDuplicates).not.toHaveBeenCalled();
    });

    it('returns a safe unavailable response when ML is down', async () => {
      prisma.report.findFirst.mockResolvedValue(source);
      prisma.report.findMany.mockResolvedValue([candidate]);
      client.detectDuplicates.mockRejectedValue(
        new MlServiceError('ml_unavailable', 'connection refused'),
      );

      const view = await service.suggestDuplicatesForStudent(
        '4301',
        'rep_src',
      );

      expect(view.available).toBe(false);
      expect(view.reason).toBe('ml_unavailable');
      expect(view.decision).toBeNull();
      expect(view.candidates).toEqual([]);
      expect(view.modelVersion).toBeNull();
      expect(view.message).toContain('No report data was changed');
      expect(prisma.report.update).not.toHaveBeenCalled();
    });
  });

  describe('pre-submission duplicate suggestions', () => {
    it('compares a draft with only the student’s reports without writing anything', async () => {
      prisma.report.findMany.mockResolvedValue([candidate, customCategoryCandidate]);
      client.detectDuplicates.mockResolvedValue(duplicateResult);

      const view = await service.suggestDuplicatesForDraft('4301', {
        description: '  The library reading-room lights keep flickering.  ',
        category: 'Electrical',
        location: '  Main   Library ',
        maxCandidates: 5,
      });

      expect(prisma.report.findMany).toHaveBeenCalledWith({
        where: { studentId: '4301' },
        orderBy: { createdAt: 'desc' },
        take: 500,
        select: expect.any(Object),
      });
      expect(client.detectDuplicates).toHaveBeenCalledWith({
        newComplaint: {
          description: 'The library reading-room lights keep flickering.',
          category: 'Electrical',
          location: 'Main Library',
        },
        existingComplaints: [
          {
            complaintId: 'rep_2',
            description: candidate.description,
            category: 'Electrical',
            location: 'Main Library',
          },
          {
            complaintId: 'rep_3',
            description: customCategoryCandidate.description,
            category: null,
            location: 'Main Library',
          },
        ],
        maxCandidates: 5,
      });
      expect(view.reportId).toBeNull();
      expect(view.available).toBe(true);
      expect(prisma.report.create).not.toHaveBeenCalled();
      expect(prisma.report.update).not.toHaveBeenCalled();
      expect(prisma.report.updateMany).not.toHaveBeenCalled();
      expect(prisma.report.delete).not.toHaveBeenCalled();
    });

    it('returns a safe unavailable preview when ML is down', async () => {
      prisma.report.findMany.mockResolvedValue([candidate]);
      client.detectDuplicates.mockRejectedValue(
        new MlServiceError('ml_timeout', 'timed out'),
      );

      const view = await service.suggestDuplicatesForDraft('4301', {
        description: 'Library lights are flickering.',
        category: null,
        location: null,
        maxCandidates: 5,
      });

      expect(view.available).toBe(false);
      expect(view.reportId).toBeNull();
      expect(view.reason).toBe('ml_timeout');
      expect(view.candidates).toEqual([]);
      expect(prisma.report.create).not.toHaveBeenCalled();
    });
  });

  describe('staff/admin duplicate suggestions', () => {
    it('rejects a non-staff principal even if a future caller bypasses the guard', async () => {
      await expect(
        service.suggestDuplicatesForStaff(
          { studentId: '4301', role: 'STUDENT' } as never,
          'rep_src',
        ),
      ).rejects.toThrow(ForbiddenException);
      expect(prisma.report.findUnique).not.toHaveBeenCalled();
    });

    it('allows STAFF only on their assignment and scopes candidates to it', async () => {
      prisma.report.findUnique.mockResolvedValue(source);
      prisma.report.findMany.mockResolvedValue([candidate]);
      client.detectDuplicates.mockResolvedValue(duplicateResult);

      await service.suggestDuplicatesForStaff(
        { staffId: 'staff-1', username: 'maintenance.ravi', role: 'STAFF' },
        'rep_src',
        5,
      );

      expect(prisma.report.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            id: { not: 'rep_src' },
            assignedStaffId: 'staff-1',
            status: { in: ['ASSIGNED', 'IN_PROGRESS', 'RESOLVED'] },
          },
        }),
      );
    });

    it('hides an unassigned or other staff report from STAFF', async () => {
      prisma.report.findUnique.mockResolvedValue({
        ...source,
        assignedStaffId: 'staff-2',
      });

      await expect(
        service.suggestDuplicatesForStaff(
          { staffId: 'staff-1', username: 'maintenance.ravi', role: 'STAFF' },
          'rep_src',
        ),
      ).rejects.toThrow(NotFoundException);
      expect(prisma.report.findMany).not.toHaveBeenCalled();
    });

    it('lets ADMIN use the full report set without changing any report', async () => {
      prisma.report.findUnique.mockResolvedValue(source);
      prisma.report.findMany.mockResolvedValue([
        candidate,
        customCategoryCandidate,
      ]);
      client.detectDuplicates.mockResolvedValue(duplicateResult);

      const view = await service.suggestDuplicatesForStaff(
        { staffId: 'admin-1', username: 'campus.admin', role: 'ADMIN' },
        'rep_src',
      );

      expect(prisma.report.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: { not: 'rep_src' } },
        }),
      );
      expect(view.candidates).toHaveLength(2);
      expect(prisma.report.create).not.toHaveBeenCalled();
      expect(prisma.report.update).not.toHaveBeenCalled();
      expect(prisma.report.delete).not.toHaveBeenCalled();
    });
  });
});
