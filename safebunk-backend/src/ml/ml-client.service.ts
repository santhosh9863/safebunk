import { Inject, Injectable } from '@nestjs/common';
import { HttpService } from '@nestjs/axios';
import { AxiosResponse, isAxiosError } from 'axios';
import { firstValueFrom } from 'rxjs';
import {
  ML_CLIENT_CONFIG,
  ML_TOKEN_HEADER,
} from './ml.constants';
import {
  CategoryDecision,
  CategoryPrediction,
  DuplicateDecision,
  DuplicateDetectionInput,
  DuplicateDetectionResult,
  MlClientConfig,
  MlFailureReason,
} from './ml.types';

/** A normalized upstream failure that never contains the service token. */
export class MlServiceError extends Error {
  constructor(
    readonly reason: MlFailureReason,
    message: string,
    readonly upstreamStatus: number | null = null,
    readonly retryable = false,
  ) {
    super(message);
    this.name = 'MlServiceError';
  }
}

interface CategoryApiResponse {
  category: string;
  confidence: number;
  model_version: string;
  manual_review_recommended: boolean;
  decision: CategoryDecision;
  threshold: number;
}

interface DuplicateApiCandidate {
  complaint_id: string;
  similarity_score: number;
  ranking_score: number;
  category: string | null;
  location: string | null;
  category_match: boolean;
  location_match: boolean;
  reasons: string[];
}

interface DuplicateApiResponse {
  decision: DuplicateDecision;
  candidates: DuplicateApiCandidate[];
  duplicate_threshold: number;
  uncertain_threshold: number;
  similarity_metric: string;
  ranking_metric: string;
  model_version: string;
  score_note: string;
  manual_review_recommended: boolean;
  action: 'suggestion_only';
  existing_complaints_evaluated: number;
  message: string;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isUnitScore(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1;
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function isCategoryDecision(value: unknown): value is CategoryDecision {
  return value === 'predict' || value === 'abstain';
}

function isDuplicateDecision(value: unknown): value is DuplicateDecision {
  return value === 'match' || value === 'uncertain' || value === 'no_match';
}

@Injectable()
export class MlClientService {
  constructor(
    private readonly httpService: HttpService,
    @Inject(ML_CLIENT_CONFIG) private readonly config: MlClientConfig,
  ) {}

  isConfigured(): boolean {
    return this.config.baseUrl !== null && this.config.serviceToken !== null;
  }

  async predictCategory(description: string): Promise<CategoryPrediction> {
    const response = await this.post<CategoryApiResponse>(
      'predict/category',
      { description },
      (data) => this.parseCategoryResponse(data),
    );

    return {
      category: response.category,
      confidence: response.confidence,
      modelVersion: response.model_version,
      manualReviewRecommended: response.manual_review_recommended,
      decision: response.decision,
      threshold: response.threshold,
    };
  }

  async detectDuplicates(input: DuplicateDetectionInput): Promise<DuplicateDetectionResult> {
    const response = await this.post<DuplicateApiResponse>(
      'detect/duplicates',
      {
        new_complaint: {
          description: input.newComplaint.description,
          category: input.newComplaint.category,
          location: input.newComplaint.location,
        },
        existing_complaints: input.existingComplaints.map((complaint) => ({
          complaint_id: complaint.complaintId,
          description: complaint.description,
          category: complaint.category,
          location: complaint.location,
        })),
        max_candidates: input.maxCandidates,
      },
      (data) => this.parseDuplicateResponse(data),
    );

    return {
      decision: response.decision,
      candidates: response.candidates.map((candidate) => ({
        complaintId: candidate.complaint_id,
        similarityScore: candidate.similarity_score,
        rankingScore: candidate.ranking_score,
        category: candidate.category,
        location: candidate.location,
        categoryMatch: candidate.category_match,
        locationMatch: candidate.location_match,
        reasons: candidate.reasons,
      })),
      duplicateThreshold: response.duplicate_threshold,
      uncertainThreshold: response.uncertain_threshold,
      similarityMetric: response.similarity_metric,
      rankingMetric: response.ranking_metric,
      modelVersion: response.model_version,
      scoreNote: response.score_note,
      manualReviewRecommended: response.manual_review_recommended,
      action: response.action,
      existingComplaintsEvaluated: response.existing_complaints_evaluated,
      message: response.message,
    };
  }

  private async post<T>(
    path: string,
    payload: unknown,
    parse: (data: unknown) => T,
  ): Promise<T> {
    const { baseUrl, serviceToken } = this.config;
    if (!baseUrl || !serviceToken) {
      throw new MlServiceError(
        'ml_not_configured',
        'The ML service URL and service token are not configured.',
      );
    }

    let lastError: MlServiceError | null = null;

    for (let attempt = 0; attempt <= this.config.maxRetries; attempt += 1) {
      let response: AxiosResponse<unknown>;
      try {
        response = await firstValueFrom(
          this.httpService.post(path, payload, {
            baseURL: `${baseUrl}/`,
            timeout: this.config.timeoutMs,
            maxRedirects: 0,
            headers: {
              Accept: 'application/json',
              'Content-Type': 'application/json',
              [ML_TOKEN_HEADER]: serviceToken,
            },
            validateStatus: () => true,
          }),
        );
      } catch (error) {
        lastError = this.mapTransportError(error);
        if (!lastError.retryable || attempt === this.config.maxRetries) {
          throw lastError;
        }
        continue;
      }

      if (response.status >= 200 && response.status < 300) {
        return parse(response.data);
      }

      if (response.status >= 400 && response.status < 500) {
        throw new MlServiceError(
          'ml_request_rejected',
          `The ML service rejected the request (HTTP ${response.status}).`,
          response.status,
        );
      }

      lastError = new MlServiceError(
        'ml_unavailable',
        `The ML service returned HTTP ${response.status}.`,
        response.status,
        true,
      );
      if (attempt === this.config.maxRetries) {
        throw lastError;
      }
    }

    throw (
      lastError ??
      new MlServiceError('ml_unavailable', 'The ML service did not respond.')
    );
  }

  private mapTransportError(error: unknown): MlServiceError {
    const code =
      isRecord(error) && typeof error.code === 'string' ? error.code : '';
    if (code === 'ECONNABORTED' || code === 'ETIMEDOUT') {
      return new MlServiceError(
        'ml_timeout',
        'The ML service request timed out.',
        null,
        true,
      );
    }
    if (isAxiosError(error)) {
      return new MlServiceError(
        'ml_unavailable',
        'The ML service could not be reached.',
        error.response?.status ?? null,
        true,
      );
    }
    return new MlServiceError(
      'ml_unavailable',
      'The ML service could not be reached.',
      null,
      true,
    );
  }

  private invalidResponse(): MlServiceError {
    return new MlServiceError(
      'ml_invalid_response',
      'The ML service returned an unexpected response.',
    );
  }

  private parseCategoryResponse(data: unknown): CategoryApiResponse {
    if (
      !isRecord(data) ||
      !isNonEmptyString(data.category) ||
      !isUnitScore(data.confidence) ||
      !isNonEmptyString(data.model_version) ||
      typeof data.manual_review_recommended !== 'boolean' ||
      !isCategoryDecision(data.decision) ||
      !isUnitScore(data.threshold)
    ) {
      throw this.invalidResponse();
    }

    return {
      category: data.category,
      confidence: data.confidence,
      model_version: data.model_version,
      manual_review_recommended: data.manual_review_recommended,
      decision: data.decision,
      threshold: data.threshold,
    };
  }

  private parseDuplicateResponse(data: unknown): DuplicateApiResponse {
    if (
      !isRecord(data) ||
      !isDuplicateDecision(data.decision) ||
      !Array.isArray(data.candidates) ||
      !isUnitScore(data.duplicate_threshold) ||
      !isUnitScore(data.uncertain_threshold) ||
      !isNonEmptyString(data.similarity_metric) ||
      !isNonEmptyString(data.ranking_metric) ||
      !isNonEmptyString(data.model_version) ||
      !isNonEmptyString(data.score_note) ||
      typeof data.manual_review_recommended !== 'boolean' ||
      data.action !== 'suggestion_only' ||
      typeof data.existing_complaints_evaluated !== 'number' ||
      !Number.isInteger(data.existing_complaints_evaluated) ||
      data.existing_complaints_evaluated < 0 ||
      typeof data.message !== 'string'
    ) {
      throw this.invalidResponse();
    }

    const candidates: DuplicateApiCandidate[] = data.candidates.map(
      (candidate: unknown) => this.parseDuplicateCandidate(candidate),
    );

    return {
      decision: data.decision,
      candidates,
      duplicate_threshold: data.duplicate_threshold,
      uncertain_threshold: data.uncertain_threshold,
      similarity_metric: data.similarity_metric,
      ranking_metric: data.ranking_metric,
      model_version: data.model_version,
      score_note: data.score_note,
      manual_review_recommended: data.manual_review_recommended,
      action: data.action,
      existing_complaints_evaluated: data.existing_complaints_evaluated,
      message: data.message,
    };
  }

  private parseDuplicateCandidate(data: unknown): DuplicateApiCandidate {
    if (
      !isRecord(data) ||
      !isNonEmptyString(data.complaint_id) ||
      !isUnitScore(data.similarity_score) ||
      !isUnitScore(data.ranking_score) ||
      !(data.category === null || typeof data.category === 'string') ||
      !(data.location === null || typeof data.location === 'string') ||
      typeof data.category_match !== 'boolean' ||
      typeof data.location_match !== 'boolean' ||
      !Array.isArray(data.reasons) ||
      !data.reasons.every((reason) => typeof reason === 'string')
    ) {
      throw this.invalidResponse();
    }

    return {
      complaint_id: data.complaint_id,
      similarity_score: data.similarity_score,
      ranking_score: data.ranking_score,
      category: data.category,
      location: data.location,
      category_match: data.category_match,
      location_match: data.location_match,
      reasons: data.reasons,
    };
  }
}
