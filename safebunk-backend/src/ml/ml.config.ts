import {
  ML_DEFAULT_MAX_RETRIES,
  ML_DEFAULT_TIMEOUT_MS,
  ML_MAX_RETRIES,
  ML_MAX_TIMEOUT_MS,
  ML_MIN_TIMEOUT_MS,
  ML_SERVICE_TOKEN_ENV,
  ML_SERVICE_URL_ENV,
  ML_TIMEOUT_ENV,
  ML_MAX_RETRIES_ENV,
} from './ml.constants';
import { MlClientConfig } from './ml.types';

function parseBoundedInteger(
  raw: string | undefined,
  fallback: number,
  min: number,
  max: number,
): number {
  if (!raw?.trim()) return fallback;
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed < min || parsed > max) {
    return fallback;
  }
  return parsed;
}

function normalizeBaseUrl(raw: string): string | null {
  try {
    const parsed = new URL(raw);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return null;
    }
    if (parsed.username || parsed.password || parsed.search || parsed.hash) {
      return null;
    }
    return raw.replace(/\/+$/, '');
  } catch {
    return null;
  }
}

/**
 * Reads the internal ML-service connection settings.
 *
 * Both values are required: a URL without the shared token would make an
 * unauthenticated server-to-server call, so the integration stays disabled
 * unless both are present and the URL is a valid HTTP(S) origin/path.
 */
export function readMlClientConfig(
  env: NodeJS.ProcessEnv = process.env,
): MlClientConfig {
  const rawUrl = env[ML_SERVICE_URL_ENV]?.trim();
  const serviceToken = env[ML_SERVICE_TOKEN_ENV]?.trim();
  const timeoutMs = parseBoundedInteger(
    env[ML_TIMEOUT_ENV],
    ML_DEFAULT_TIMEOUT_MS,
    ML_MIN_TIMEOUT_MS,
    ML_MAX_TIMEOUT_MS,
  );
  const maxRetries = parseBoundedInteger(
    env[ML_MAX_RETRIES_ENV],
    ML_DEFAULT_MAX_RETRIES,
    0,
    ML_MAX_RETRIES,
  );

  if (!rawUrl || !serviceToken) {
    return { baseUrl: null, serviceToken: null, timeoutMs, maxRetries };
  }

  const baseUrl = normalizeBaseUrl(rawUrl);
  if (!baseUrl) {
    return { baseUrl: null, serviceToken: null, timeoutMs, maxRetries };
  }

  return { baseUrl, serviceToken, timeoutMs, maxRetries };
}
