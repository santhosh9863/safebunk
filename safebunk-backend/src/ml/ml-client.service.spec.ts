import { of, throwError } from 'rxjs';
import { MlClientService, MlServiceError } from './ml-client.service';
import { ML_TOKEN_HEADER } from './ml.constants';
import { MlClientConfig } from './ml.types';

const CONFIG: MlClientConfig = {
  baseUrl: 'http://127.0.0.1:8001',
  serviceToken: 'shared-secret',
  timeoutMs: 1_500,
  maxRetries: 1,
};

function response(status: number, data: unknown) {
  return {
    status,
    data,
    statusText: '',
    headers: {},
    config: {},
  };
}

function makeClient(config: MlClientConfig = CONFIG) {
  const http = {
    post: jest.fn(),
  };
  return {
    client: new MlClientService(http as never, config),
    http,
  };
}

const categoryResponse = {
  category: 'Plumbing',
  confidence: 0.81,
  model_version: '0.1.0',
  manual_review_recommended: false,
  decision: 'predict',
  threshold: 0.2,
};

const duplicateResponse = {
  decision: 'match',
  candidates: [
    {
      complaint_id: 'rep_1',
      similarity_score: 0.72,
      ranking_score: 0.76,
      category: 'Electrical',
      location: 'Main Library',
      category_match: true,
      location_match: true,
      reasons: ['similar description text', 'same category: Electrical'],
    },
  ],
  duplicate_threshold: 0.5,
  uncertain_threshold: 0.4,
  similarity_metric: 'tfidf_cosine_similarity',
  ranking_metric: 'cosine_similarity_with_metadata_support',
  model_version: '0.2.0',
  score_note: 'Ranking score, not a probability.',
  manual_review_recommended: true,
  action: 'suggestion_only',
  existing_complaints_evaluated: 3,
  message: 'Potential duplicates found; these are suggestions only.',
};

async function captureError(action: Promise<unknown>): Promise<MlServiceError> {
  try {
    await action;
  } catch (error) {
    return error as MlServiceError;
  }
  throw new Error('Expected the action to reject');
}

describe('MlClientService', () => {
  it('stays disabled when the URL or shared token is missing', async () => {
    const { client, http } = makeClient({
      ...CONFIG,
      baseUrl: null,
      serviceToken: null,
    });

    const error = await captureError(
      client.predictCategory('A leaking pipe under the sink.'),
    );

    expect(error).toBeInstanceOf(MlServiceError);
    expect(error.reason).toBe('ml_not_configured');
    expect(http.post).not.toHaveBeenCalled();
  });

  it('sends the shared token and returns a category suggestion', async () => {
    const { client, http } = makeClient();
    http.post.mockReturnValue(of(response(200, categoryResponse)));

    const prediction = await client.predictCategory(
      'A water pipe is leaking under the sink.',
    );

    expect(prediction).toEqual({
      category: 'Plumbing',
      confidence: 0.81,
      modelVersion: '0.1.0',
      manualReviewRecommended: false,
      decision: 'predict',
      threshold: 0.2,
    });
    expect(http.post).toHaveBeenCalledWith(
      'predict/category',
      { description: 'A water pipe is leaking under the sink.' },
      expect.objectContaining({
        baseURL: 'http://127.0.0.1:8001/',
        timeout: 1_500,
        maxRedirects: 0,
        headers: expect.objectContaining({
          [ML_TOKEN_HEADER]: 'shared-secret',
        }),
      }),
    );
  });

  it('maps a duplicate response without exposing snake_case to callers', async () => {
    const { client, http } = makeClient();
    http.post.mockReturnValue(of(response(200, duplicateResponse)));

    const result = await client.detectDuplicates({
      newComplaint: {
        description: 'The lights in the library are flickering.',
        category: 'Electrical',
        location: 'Main Library',
      },
      existingComplaints: [
        {
          complaintId: 'rep_1',
          description: 'Library lights are flashing.',
          category: 'Electrical',
          location: 'Main Library',
        },
      ],
      maxCandidates: 5,
    });

    expect(result.modelVersion).toBe('0.2.0');
    expect(result.decision).toBe('match');
    expect(result.candidates[0]).toEqual({
      complaintId: 'rep_1',
      similarityScore: 0.72,
      rankingScore: 0.76,
      category: 'Electrical',
      location: 'Main Library',
      categoryMatch: true,
      locationMatch: true,
      reasons: ['similar description text', 'same category: Electrical'],
    });
    expect(http.post).toHaveBeenCalledWith(
      'detect/duplicates',
      {
        new_complaint: {
          description: 'The lights in the library are flickering.',
          category: 'Electrical',
          location: 'Main Library',
        },
        existing_complaints: [
          {
            complaint_id: 'rep_1',
            description: 'Library lights are flashing.',
            category: 'Electrical',
            location: 'Main Library',
          },
        ],
        max_candidates: 5,
      },
      expect.any(Object),
    );
  });

  it('does not retry an upstream 4xx response', async () => {
    const { client, http } = makeClient();
    http.post.mockReturnValue(
      of(response(422, { detail: { code: 'invalid_input' } })),
    );

    const error = await captureError(
      client.predictCategory('A leaking pipe under the sink.'),
    );

    expect(error.reason).toBe('ml_request_rejected');
    expect(error.upstreamStatus).toBe(422);
    expect(http.post).toHaveBeenCalledTimes(1);
  });

  it('retries a bounded number of times on upstream 5xx', async () => {
    const { client, http } = makeClient();
    http.post.mockReturnValue(of(response(503, { detail: 'missing model' })));

    const error = await captureError(
      client.predictCategory('A leaking pipe under the sink.'),
    );

    expect(error.reason).toBe('ml_unavailable');
    expect(error.upstreamStatus).toBe(503);
    expect(http.post).toHaveBeenCalledTimes(2);
  });

  it('maps and retries a timeout safely', async () => {
    const { client, http } = makeClient();
    http.post.mockReturnValue(
      throwError(() => Object.assign(new Error('timeout'), { code: 'ETIMEDOUT' })),
    );

    const error = await captureError(
      client.predictCategory('A leaking pipe under the sink.'),
    );

    expect(error.reason).toBe('ml_timeout');
    expect(http.post).toHaveBeenCalledTimes(2);
  });

  it('maps a connection failure to unavailable', async () => {
    const { client, http } = makeClient({
      ...CONFIG,
      maxRetries: 0,
    });
    http.post.mockReturnValue(
      throwError(() =>
        Object.assign(new Error('connect ECONNREFUSED'), {
          code: 'ECONNREFUSED',
        }),
      ),
    );

    const error = await captureError(
      client.detectDuplicates({
        newComplaint: {
          description: 'A leaking pipe under the sink.',
          category: null,
          location: null,
        },
        existingComplaints: [],
        maxCandidates: 5,
      }),
    );

    expect(error.reason).toBe('ml_unavailable');
    expect(http.post).toHaveBeenCalledTimes(1);
  });

  it('rejects an unexpected success payload as invalid', async () => {
    const { client, http } = makeClient();
    http.post.mockReturnValue(of(response(200, { category: 'Plumbing' })));

    const error = await captureError(
      client.predictCategory('A leaking pipe under the sink.'),
    );

    expect(error.reason).toBe('ml_invalid_response');
    expect(http.post).toHaveBeenCalledTimes(1);
  });
});
