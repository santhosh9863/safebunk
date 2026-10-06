/**
 * Server-side notification event catalogue (shared by watchers, rule engine,
 * content service and scheduler). Mirror of the Flutter-side
 * NotificationType, restricted to what the backend can legitimately detect.
 */
export type NotificationEventType =
  // Attendance marked on Linways
  | 'attendanceMarkedPresent'
  | 'attendanceMarkedAbsent'
  // Attendance percentage transitions
  | 'attendanceImproved'
  | 'attendanceDropped'
  | 'enteredSafeZone'
  | 'leftSafeZone'
  | 'enteredDangerZone'
  | 'recoveredFromDanger'
  | 'perfectAttendance'
  // Milestones
  | 'reached80'
  | 'reached90'
  | 'reached95'
  // Class reminders (server-scheduled from the real timetable)
  | 'classReminder30Min'
  | 'classReminder10Min'
  | 'classReminder5Min'
  | 'classStarting'
  | 'classMissed'
  | 'nextClass'
  // Day-level facts
  | 'dayWrapUp'
  | 'sundayChill'
  // Timetable
  | 'timetableUpdated'
  // System
  | 'testNotification';

export interface NotificationEventPayload {
  type: NotificationEventType;
  subjectName?: string;
  /** Faculty name for the class (used for respectful, gender-safe wording). */
  staffName?: string;
  percentage?: number;
  target?: number;
  minutes?: number;
  [key: string]: unknown;
}

/** How long FCM may hold a message for offline devices (in seconds). */
export function ttlSecondsFor(type: NotificationEventType): number {
  switch (type) {
    // Time-sensitive: never deliver a stale class reminder late.
    case 'classReminder30Min':
    case 'classReminder10Min':
    case 'classReminder5Min':
    case 'classStarting':
    case 'classMissed':
    case 'nextClass':
      return 10 * 60; // 10 minutes
    case 'timetableUpdated':
    case 'dayWrapUp':
    case 'sundayChill':
      return 60 * 60; // 1 hour
    default:
      // State notifications (attendance marked / zones / milestones).
      return 60 * 60; // 1 hour
  }
}

/** Priority bucket → Android notification channel id (must exist in app). */
export function channelIdFor(type: NotificationEventType): string {
  switch (type) {
    case 'enteredDangerZone':
    case 'classMissed':
      return 'attendance_alerts';
    default:
      return 'reminders';
  }
}
