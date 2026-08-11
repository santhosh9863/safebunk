/// The kinds of events the notification system can raise.
///
/// Each type maps to real, verified app data — the rule engine never invents
/// facts. Content wording lives in the content service, not here.
enum NotificationType {
  // ── Attendance ──
  attendanceImproved,
  attendanceDropped,
  enteredSafeZone,
  leftSafeZone,
  enteredWarningZone,
  enteredDangerZone,
  recoveredFromDanger,
  perfectAttendance,

  // ── Bunking ──
  safeToBunk,
  lastSafeBunk,
  noSafeBunks,
  bunkWouldCauseDanger,
  bunkWouldCrossSafeThreshold,

  // ── Class / Timetable ──
  classReminder30Min,
  classReminder10Min,
  classReminder5Min,
  classStarting,
  classMissed,
  nextClass,
  heavyClassDay,
  lightClassDay,
  earlyClass,
  longClassGap,
  noClasses,

  // ── Milestones ──
  reached75,
  reached80,
  reached90,
  reached95,
  reached100,

  // ── System ──
  syncSuccess,
  syncFailure,
  offline,
  timetableUpdated,
}
