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
 * Explicit, auditable state machine:
 *   SUBMITTED  → ASSIGNED | REJECTED
 *   ASSIGNED   → IN_PROGRESS | REJECTED
 *   IN_PROGRESS→ RESOLVED | REJECTED
 *   RESOLVED / REJECTED are terminal.
 *
 * REJECTED is a state-valid transition from any non-terminal status, but the
 * service/controller additionally require an ADMIN actor and a non-empty
 * reason. STAFF can only accept, note progress and resolve their own reports.
 */
const ALLOWED_TRANSITIONS: Readonly<Record<ReportStatus, readonly ReportStatus[]>> = {
  SUBMITTED: ['ASSIGNED', 'REJECTED'],
  ASSIGNED: ['IN_PROGRESS', 'REJECTED'],
  IN_PROGRESS: ['RESOLVED', 'REJECTED'],
  RESOLVED: [],
  REJECTED: [],
};

/** Statuses an administrator may explicitly reject, with a recorded reason. */
export const REJECTABLE_STATUSES: readonly ReportStatus[] = [
  'SUBMITTED',
  'ASSIGNED',
  'IN_PROGRESS',
];

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
