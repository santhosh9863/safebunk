import {
  ALL_REPORT_PRIORITIES,
  ALL_REPORT_STATUSES,
  InvalidReportTransitionError,
  assertTransition,
  canTransition,
  isReportPriority,
  isReportStatus,
} from './report-status';

describe('report status state machine', () => {
  it('allows exactly the approved transitions', () => {
    expect(canTransition('SUBMITTED', 'ASSIGNED')).toBe(true);
    expect(canTransition('SUBMITTED', 'REJECTED')).toBe(true);
    expect(canTransition('ASSIGNED', 'IN_PROGRESS')).toBe(true);
    expect(canTransition('IN_PROGRESS', 'RESOLVED')).toBe(true);
  });

  it('rejects every other transition', () => {
    expect(canTransition('SUBMITTED', 'IN_PROGRESS')).toBe(false);
    expect(canTransition('SUBMITTED', 'RESOLVED')).toBe(false);
    expect(canTransition('ASSIGNED', 'RESOLVED')).toBe(false);
    expect(canTransition('RESOLVED', 'IN_PROGRESS')).toBe(false);
    expect(canTransition('REJECTED', 'SUBMITTED')).toBe(false);
    expect(canTransition('RESOLVED', 'REJECTED')).toBe(false);
    expect(canTransition('IN_PROGRESS', 'REJECTED')).toBe(false);
    expect(canTransition('ASSIGNED', 'REJECTED')).toBe(false);
  });

  it('treats RESOLVED and REJECTED as terminal', () => {
    for (const terminal of ['RESOLVED', 'REJECTED'] as const) {
      for (const to of ALL_REPORT_STATUSES) {
        expect(canTransition(terminal, to)).toBe(false);
      }
    }
  });

  it('assertTransition throws InvalidReportTransitionError on bad move', () => {
    expect(() => assertTransition('SUBMITTED', 'RESOLVED')).toThrow(
      InvalidReportTransitionError,
    );
    expect(assertTransition('SUBMITTED', 'ASSIGNED')).toBe('ASSIGNED');
  });

  it('guards enums', () => {
    expect(isReportStatus('SUBMITTED')).toBe(true);
    expect(isReportStatus('BOGUS')).toBe(false);
    expect(isReportPriority('CRITICAL')).toBe(true);
    expect(isReportPriority('URGENT')).toBe(false);
    expect(ALL_REPORT_PRIORITIES).toEqual(['LOW', 'MEDIUM', 'HIGH', 'CRITICAL']);
  });
});
