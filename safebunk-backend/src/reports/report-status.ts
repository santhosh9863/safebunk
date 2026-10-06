export type ReportStatus =
  | 'SUBMITTED'
  | 'ASSIGNED'
  | 'IN_PROGRESS'
  | 'RESOLVED'
  | 'REJECTED';

export type ReportPriority = 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';

/** Terminal statuses accept no further transitions. */
export const TERMINAL_STATUSES: readonly ReportStatus[] = ['RESOLVED', 'REJECTED'];

/**
 * Explicit, auditable state machine (docs/REPORTS_SCHEMA.md §5):
 *   SUBMITTED  → ASSIGNED | REJECTED
 *   ASSIGNED   → IN_PROGRESS
 *   IN_PROGRESS→ RESOLVED
 * Status mutation endpoints are NOT exposed in Phase 1; this module exists so
 * Phase 6 only has to wire guarded endpoints to a tested transition table.
 */
const ALLOWED_TRANSITIONS: Readonly<Record<ReportStatus, readonly ReportStatus[]>> = {
  SUBMITTED: ['ASSIGNED', 'REJECTED'],
  ASSIGNED: ['IN_PROGRESS'],
  IN_PROGRESS: ['RESOLVED'],
  RESOLVED: [],
  REJECTED: [],
};

export const ALL_REPORT_STATUSES: readonly ReportStatus[] = [
  'SUBMITTED',
  'ASSIGNED',
  'IN_PROGRESS',
  'RESOLVED',
  'REJECTED',
];

export const ALL_REPORT_PRIORITIES: readonly ReportPriority[] = [
  'LOW',
  'MEDIUM',
  'HIGH',
  'CRITICAL',
];

export function isReportStatus(value: string): value is ReportStatus {
  return (ALL_REPORT_STATUSES as readonly string[]).includes(value);
}

export function isReportPriority(value: string): value is ReportPriority {
  return (ALL_REPORT_PRIORITIES as readonly string[]).includes(value);
}

export function canTransition(from: ReportStatus, to: ReportStatus): boolean {
  return ALLOWED_TRANSITIONS[from].includes(to);
}

export class InvalidReportTransitionError extends Error {
  constructor(
    readonly from: string,
    readonly to: string,
  ) {
    super(`Invalid report status transition: ${from} -> ${to}`);
    this.name = 'InvalidReportTransitionError';
  }
}

/** Returns the next status or throws InvalidReportTransitionError. */
export function assertTransition(from: ReportStatus, to: ReportStatus): ReportStatus {
  if (!canTransition(from, to)) {
    throw new InvalidReportTransitionError(from, to);
  }
  return to;
}
