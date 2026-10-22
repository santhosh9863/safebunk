export type MlFailureReason =
  | 'ml_not_configured'
  | 'ml_timeout'
  | 'ml_unavailable'
  | 'ml_request_rejected'
  | 'ml_invalid_response';

export type CategoryDecision = 'predict' | 'abstain';
export type DuplicateDecision = 'match' | 'uncertain' | 'no_match';

export interface MlClientConfig {
  /** Normalized base URL, or null when the integration is not configured. */
  baseUrl: string | null;
  /** Shared server-to-server secret, or null when it is not configured. */
  serviceToken: string | null;
  timeoutMs: number;
  maxRetries: number;
}

export interface CategoryPrediction {
  category: string;
  confidence: number;
  modelVersion: string;
  manualReviewRecommended: boolean;
  decision: CategoryDecision;
  threshold: number;
}

export interface CategorySuggestionView {
  available: boolean;
  suggestionOnly: true;
  reason: MlFailureReason | null;
  message: string;
  category: string | null;
  confidence: number | null;
  modelVersion: string | null;
  manualReviewRecommended: boolean;
  decision: CategoryDecision | 'unavailable';
  threshold: number | null;
}

export interface ExistingComplaintInput {
  complaintId: string;
  description: string;
  category: string | null;
  location: string | null;
}

export interface NewComplaintInput {
  description: string;
  category: string | null;
  location: string | null;
}

export interface DraftDuplicateInput extends NewComplaintInput {
  maxCandidates: number;
}

export interface DuplicateDetectionInput {
  newComplaint: NewComplaintInput;
  existingComplaints: ExistingComplaintInput[];
  maxCandidates: number;
}

export interface DuplicateCandidateScore {
  complaintId: string;
  similarityScore: number;
  rankingScore: number;
  category: string | null;
  location: string | null;
  categoryMatch: boolean;
  locationMatch: boolean;
  reasons: string[];
}

export interface DuplicateDetectionResult {
  decision: DuplicateDecision;
  candidates: DuplicateCandidateScore[];
  duplicateThreshold: number;
  uncertainThreshold: number;
  similarityMetric: string;
  rankingMetric: string;
  modelVersion: string;
  scoreNote: string;
  manualReviewRecommended: boolean;
  action: 'suggestion_only';
  existingComplaintsEvaluated: number;
  message: string;
}

export interface DuplicateCandidateView {
  reportId: string;
  reportCode: string;
  title: string;
  status: string;
  category: string | null;
  location: string | null;
  similarityScore: number;
  rankingScore: number;
  categoryMatch: boolean;
  locationMatch: boolean;
  reasons: string[];
}

export interface DuplicateSuggestionView {
  available: boolean;
  suggestionOnly: true;
  action: 'suggestion_only';
  reason: MlFailureReason | null;
  /** The source report id, or null for a pre-submission draft preview. */
  reportId: string | null;
  decision: DuplicateDecision | null;
  candidates: DuplicateCandidateView[];
  duplicateThreshold: number | null;
  uncertainThreshold: number | null;
  similarityMetric: string | null;
  rankingMetric: string | null;
  modelVersion: string | null;
  scoreNote: string;
  manualReviewRecommended: boolean;
  existingComplaintsEvaluated: number | null;
  message: string;
}
