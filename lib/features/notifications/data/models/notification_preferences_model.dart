/// Class reminder lead time options.
enum ClassReminderTiming { minutes30, minutes10, minutes5 }

extension ClassReminderTimingMinutes on ClassReminderTiming {
  /// Lead time in minutes for this timing option.
  int get minutes => switch (this) {
        ClassReminderTiming.minutes30 => 30,
        ClassReminderTiming.minutes10 => 10,
        ClassReminderTiming.minutes5 => 5,
      };
}

/// User-controllable notification preferences.
///
/// Defaults (per product spec): everything ON, roasting ON, 10-minute
/// reminders.
class NotificationPreferences {
  final bool masterEnabled;
  final bool attendanceEnabled;
  final bool bunkEnabled;
  final bool classRemindersEnabled;
  final bool milestonesEnabled;
  final bool timetableEnabled;
  final bool roastingEnabled;
  final ClassReminderTiming reminderTiming;

  const NotificationPreferences({
    this.masterEnabled = true,
    this.attendanceEnabled = true,
    this.bunkEnabled = true,
    this.classRemindersEnabled = true,
    this.milestonesEnabled = true,
    this.timetableEnabled = true,
    this.roastingEnabled = true,
    this.reminderTiming = ClassReminderTiming.minutes10,
  });

  NotificationPreferences copyWith({
    bool? masterEnabled,
    bool? attendanceEnabled,
    bool? bunkEnabled,
    bool? classRemindersEnabled,
    bool? milestonesEnabled,
    bool? timetableEnabled,
    bool? roastingEnabled,
    ClassReminderTiming? reminderTiming,
  }) {
    return NotificationPreferences(
      masterEnabled: masterEnabled ?? this.masterEnabled,
      attendanceEnabled: attendanceEnabled ?? this.attendanceEnabled,
      bunkEnabled: bunkEnabled ?? this.bunkEnabled,
      classRemindersEnabled: classRemindersEnabled ?? this.classRemindersEnabled,
      milestonesEnabled: milestonesEnabled ?? this.milestonesEnabled,
      timetableEnabled: timetableEnabled ?? this.timetableEnabled,
      roastingEnabled: roastingEnabled ?? this.roastingEnabled,
      reminderTiming: reminderTiming ?? this.reminderTiming,
    );
  }

  /// Reminder lead time in minutes for the configured timing.
  int get reminderLeadMinutes => reminderTiming.minutes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationPreferences &&
          masterEnabled == other.masterEnabled &&
          attendanceEnabled == other.attendanceEnabled &&
          bunkEnabled == other.bunkEnabled &&
          classRemindersEnabled == other.classRemindersEnabled &&
          milestonesEnabled == other.milestonesEnabled &&
          timetableEnabled == other.timetableEnabled &&
          roastingEnabled == other.roastingEnabled &&
          reminderTiming == other.reminderTiming;

  @override
  int get hashCode => Object.hash(
        masterEnabled,
        attendanceEnabled,
        bunkEnabled,
        classRemindersEnabled,
        milestonesEnabled,
        timetableEnabled,
        roastingEnabled,
        reminderTiming,
      );
}
