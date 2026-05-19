class NotificationChannels {
  static const attendanceAlerts = _Channel(
    id: 'attendance_alerts',
    name: 'Attendance Alerts',
    description: 'Notifications about attendance threshold changes.',
  );

  static const reminders = _Channel(
    id: 'reminders',
    name: 'Reminders',
    description: 'Gentle reminders to check your attendance.',
  );

  static const summaries = _Channel(
    id: 'summaries',
    name: 'Summaries',
    description: 'Weekly attendance summary notifications.',
  );
}

class _Channel {
  final String id;
  final String name;
  final String description;
  const _Channel({required this.id, required this.name, required this.description});
}

class NotificationIds {
  static const lowAttendance = 1001;
  static const safeLeaveAvailable = 1002;
  static const dailyReminder = 1003;
  static const weeklySummary = 1004;
}

class SafeLeaveMilestones {
  static const List<int> values = [5, 10, 25, 50];
}

class NotificationStoreKeys {
  static const firstRunComplete = 'first_run_complete';
  static const lowWarningActive = 'low_warning_active';
  static const lastProcessedPercentage = 'last_processed_pct';
  static const lowWarningCooldownUntil = 'low_warning_cooldown';
  static const lastSafeBunks = 'last_safe_bunks';
  static const lastDailyReminder = 'last_daily_reminder';
  static const lastSummaryMonday = 'last_summary_monday';
}
