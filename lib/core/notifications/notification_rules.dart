import 'notification_models.dart';

class LowAttendanceResult {
  final bool shouldNotify;
  final bool isActive;
  final bool crossedBelow;
  final bool recovered;

  const LowAttendanceResult({
    required this.shouldNotify,
    required this.isActive,
    required this.crossedBelow,
    required this.recovered,
  });

  static const none = LowAttendanceResult(
    shouldNotify: false,
    isActive: false,
    crossedBelow: false,
    recovered: false,
  );
}

class SafeLeavesResult {
  final bool shouldNotify;
  final int newLastNotifiedBunks;

  const SafeLeavesResult({
    required this.shouldNotify,
    required this.newLastNotifiedBunks,
  });
}

class DailyReminderResult {
  final bool shouldNotify;
  final bool shouldUpdateDate;

  const DailyReminderResult({
    required this.shouldNotify,
    required this.shouldUpdateDate,
  });

  static const none = DailyReminderResult(
    shouldNotify: false,
    shouldUpdateDate: false,
  );
}

class WeeklySummaryResult {
  final bool shouldNotify;
  final bool shouldUpdateWeek;

  const WeeklySummaryResult({
    required this.shouldNotify,
    required this.shouldUpdateWeek,
  });

  static const none = WeeklySummaryResult(
    shouldNotify: false,
    shouldUpdateWeek: false,
  );
}

class NotificationRules {
  NotificationRules._();

  static LowAttendanceResult evaluateLowAttendance({
    required double currentPercentage,
    required double attendanceTarget,
    required double? lastPercentage,
    required bool cooldownActive,
  }) {
    final isBelow = currentPercentage < attendanceTarget;
    final wasBelow = lastPercentage != null && lastPercentage < attendanceTarget;

    final crossedBelow = lastPercentage != null && lastPercentage >= attendanceTarget && isBelow;
    final recovered = !isBelow && wasBelow;

    if (crossedBelow && !cooldownActive) {
      return LowAttendanceResult(
        shouldNotify: true,
        isActive: true,
        crossedBelow: true,
        recovered: false,
      );
    }

    if (recovered) {
      return LowAttendanceResult(
        shouldNotify: false,
        isActive: false,
        crossedBelow: false,
        recovered: true,
      );
    }

    return LowAttendanceResult(
      shouldNotify: false,
      isActive: isBelow,
      crossedBelow: false,
      recovered: false,
    );
  }

  static SafeLeavesResult evaluateSafeLeaves({
    required int currentSafeBunks,
    required int lastNotifiedBunks,
  }) {
    if (currentSafeBunks > 0 && currentSafeBunks != lastNotifiedBunks) {
      return SafeLeavesResult(
        shouldNotify: true,
        newLastNotifiedBunks: currentSafeBunks,
      );
    }

    return SafeLeavesResult(
      shouldNotify: false,
      newLastNotifiedBunks: lastNotifiedBunks,
    );
  }

  static DailyReminderResult evaluateDailyReminder({
    required String todayDate,
    String? lastReminderDate,
  }) {
    if (lastReminderDate == null || lastReminderDate != todayDate) {
      return DailyReminderResult(
        shouldNotify: true,
        shouldUpdateDate: true,
      );
    }

    return DailyReminderResult.none;
  }

  static WeeklySummaryResult evaluateWeeklySummary({
    required String currentMonday,
    String? lastSummaryMonday,
  }) {
    if (lastSummaryMonday == null || lastSummaryMonday != currentMonday) {
      return WeeklySummaryResult(
        shouldNotify: true,
        shouldUpdateWeek: true,
      );
    }

    return WeeklySummaryResult.none;
  }

  static String mondayOfWeek(DateTime date) {
    final weekday = date.weekday;
    final monday = date.subtract(Duration(days: weekday - 1));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }

  static String todayString(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static NotificationContent contentForLowAttendance() {
    return const NotificationContent(
      title: 'Attendance Alert',
      body: "You're getting close to your attendance limit.",
    );
  }

  static NotificationContent contentForSafeLeaves(int count) {
    return NotificationContent(
      title: 'Leaves Available',
      body: 'You can safely take $count leave${count == 1 ? '' : 's'} this week.',
    );
  }

  static NotificationContent contentForDailyReminder() {
    return const NotificationContent(
      title: 'Daily Check',
      body: 'Quick check \u2014 stay updated with today\u2019s attendance.',
    );
  }

  static NotificationContent contentForWeeklySummary(double percentage) {
    return NotificationContent(
      title: 'Weekly Summary',
      body: 'Your attendance this week is ${percentage.toStringAsFixed(1)}%.',
    );
  }
}
