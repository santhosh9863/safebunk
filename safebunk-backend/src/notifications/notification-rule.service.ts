import { Injectable } from '@nestjs/common';
import { NotificationEventType } from './notification-events';

export interface AttendanceTransitionResult {
  /** The single best event for this transition, if any. */
  event: NotificationEventType | null;
  /** Milestone events also crossed (may be empty). */
  milestones: NotificationEventType[];
}

/**
 * Server-side rule engine — mirrors the logic of the Flutter rule engine so
 * both sides make identical decisions. Pure and side-effect free. One event
 * per evaluation (never spams the same transition twice).
 *
 * Zones match the app UI:
 *   safe    = percentage >= target  (default 75)
 *   danger  = percentage <  danger  (default 60)
 */
@Injectable()
export class NotificationRuleService {
  static readonly DEFAULT_TARGET = 75;
  static readonly DEFAULT_DANGER = 60;

  private static round(value: number): number {
    return Math.round(value * 100) / 100;
  }

  evaluateAttendanceTransition(
    previousPercentage: number | null,
    currentPercentage: number,
    target: number = NotificationRuleService.DEFAULT_TARGET,
    danger: number = NotificationRuleService.DEFAULT_DANGER,
  ): AttendanceTransitionResult {
    if (previousPercentage === null) {
      return { event: null, milestones: [] };
    }

    const cur = NotificationRuleService.round(currentPercentage);
    const prev = NotificationRuleService.round(previousPercentage);

    if (cur === prev) {
      return { event: null, milestones: [] };
    }

    const event: NotificationEventType | null =
      cur >= 100 && prev < 100
        ? 'perfectAttendance'
        : cur < danger && prev >= danger
          ? 'enteredDangerZone'
          : cur >= target && prev < target
            ? 'enteredSafeZone'
            : prev >= target && cur < target
              ? 'leftSafeZone'
              : cur < prev
                ? 'attendanceDropped'
                : prev < danger && cur >= danger
                  ? 'recoveredFromDanger'
                  : cur > prev
                    ? 'attendanceImproved'
                    : null;

    return { event, milestones: this.evaluateMilestones(prev, cur) };
  }

  evaluateMilestones(previousPercentage: number, currentPercentage: number): NotificationEventType[] {
    if (currentPercentage <= previousPercentage) return [];
    const events: NotificationEventType[] = [];
    const thresholds: Array<[number, NotificationEventType]> = [
      [80, 'reached80'],
      [90, 'reached90'],
      [95, 'reached95'],
    ];
    for (const [threshold, type] of thresholds) {
      if (previousPercentage < threshold && currentPercentage >= threshold) {
        events.push(type);
      }
    }
    return events;
  }

  /** Map a raw Linways attendance status code to an event type (or null). */
  statusToEvent(status: string): 'attendanceMarkedPresent' | 'attendanceMarkedAbsent' | null {
    switch (status) {
      case '1':
        return 'attendanceMarkedPresent';
      case '0':
        return 'attendanceMarkedAbsent';
      default:
        // '2' leave / '3' duty leave — no notification.
        return null;
    }
  }
}
