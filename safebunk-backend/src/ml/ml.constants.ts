/** Environment and transport constants for the internal ML service. */

export const ML_CLIENT_CONFIG = Symbol('ML_CLIENT_CONFIG');

export const ML_SERVICE_URL_ENV = 'PULSE_ML_SERVICE_URL';
export const ML_SERVICE_TOKEN_ENV = 'PULSE_ML_SERVICE_TOKEN';
export const ML_TIMEOUT_ENV = 'PULSE_ML_TIMEOUT_MS';
export const ML_MAX_RETRIES_ENV = 'PULSE_ML_MAX_RETRIES';

export const ML_TOKEN_HEADER = 'X-PULSE-ML-Token';

export const ML_DEFAULT_TIMEOUT_MS = 2_000;
export const ML_MIN_TIMEOUT_MS = 100;
export const ML_MAX_TIMEOUT_MS = 10_000;
export const ML_DEFAULT_MAX_RETRIES = 1;
export const ML_MAX_RETRIES = 2;

/** Mirrors the supported labels in the Python classifier. */
export const SUPPORTED_REPORT_CATEGORIES = [
  'Infrastructure',
  'Electrical',
  'Plumbing',
  'Cleanliness',
  'Safety',
  'Network / IT',
  'Academic',
  'Other',
] as const;

export const SUPPORTED_REPORT_CATEGORY_SET = new Set<string>(
  SUPPORTED_REPORT_CATEGORIES,
);

export const MAX_EXISTING_COMPLAINTS = 500;
export const DEFAULT_MAX_DUPLICATE_CANDIDATES = 5;
export const MAX_DUPLICATE_CANDIDATES = 20;
