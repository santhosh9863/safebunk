import '../enums/notification_type.dart';
import '../entities/notification_event.dart';

/// Pure, side-effect-free decision engine.
///
/// Turns verified attendance/bunk state into [NotificationEvent]s. It never
/// invents data and never contains user-facing wording. All inputs come from
/// the caller (which reads them from existing app providers).
///
/// Zone thresholds follow the same zones the UI uses (see
/// `computeThresholds` in settings_providers.dart):
///   safe    = percentage >= [target]        (default 75)
///   warning = [dangerThreshold] .. <target  (default 60)
///   danger  = percentage <  [dangerThreshold]
class NotificationRuleEngine {
  const NotificationRuleEngine();

  static const List<double> milestoneThresholds = [80, 90, 95];

  /// Evaluate the OVERALL attendance percentage transition.
  ///
  /// Returns at most one event per evaluation so the user is never spammed
  /// with cascading zone + direction messages for the same change.
  ///
  /// When [previousPercentage] is null (first sync after login) no event is
  /// emitted — the caller stores the baseline silently.
  List<NotificationEvent> evaluateAttendance({
    required double currentPercentage,
    double? previousPercentage,
    double target = 75,
    double dangerThreshold = 60,
  }) {
    if (previousPercentage == null) {
      return const [];
    }

    final cur = _round(currentPercentage);
    final prev = _round(previousPercentage);

    if (cur == prev) {
      return const [];
    }

    final isDanger = cur < dangerThreshold;
    final wasDanger = prev < dangerThreshold;
    final isSafe = cur >= target;
    final wasSafe = prev >= target;
    // 1. Perfect attendance.
    if (cur >= 100 && prev < 100) {
      return [NotificationEvent(type: NotificationType.perfectAttendance, attendancePercentage: cur, previousPercentage: prev)];
    }

    // 2. Crossed into the danger zone (spec: 60 -> 59 => enteredDangerZone).
    if (isDanger && !wasDanger) {
      return [NotificationEvent(type: NotificationType.enteredDangerZone, attendancePercentage: cur, previousPercentage: prev)];
    }

    // 3. Crossed back into the safe zone (spec: 74 -> 76 => enteredSafeZone).
    if (isSafe && !wasSafe) {
      return [NotificationEvent(type: NotificationType.enteredSafeZone, attendancePercentage: cur, previousPercentage: prev)];
    }

    // 4. Direction change (spec: 75 -> 68 => attendanceDropped).
    if (cur < prev) {
      return [NotificationEvent(type: NotificationType.attendanceDropped, attendancePercentage: cur, previousPercentage: prev)];
    }

    // 5. Climbed out of danger but not yet back to safe
    //    (59 -> 62: still warning, but no longer danger).
    if (prev < dangerThreshold && cur >= dangerThreshold) {
      return [NotificationEvent(type: NotificationType.recoveredFromDanger, attendancePercentage: cur, previousPercentage: prev)];
    }

    // 6. Direction improvement.
    if (cur > prev) {
      return [NotificationEvent(type: NotificationType.attendanceImproved, attendancePercentage: cur, previousPercentage: prev)];
    }

    return const [];
  }

  /// Evaluate milestones crossed UPWARD (80 / 90 / 95).
  ///
  /// Crossing 75 is reported as [NotificationType.enteredSafeZone] and
  /// reaching 100 as [NotificationType.perfectAttendance], so those are not
  /// duplicated here.
  List<NotificationEvent> evaluateMilestones({
    required double currentPercentage,
    double? previousPercentage,
  }) {
    if (previousPercentage == null) return const [];
    final cur = _round(currentPercentage);
    final prev = _round(previousPercentage);
    if (cur <= prev) return const [];

    final events = <NotificationEvent>[];
    for (final threshold in milestoneThresholds) {
      if (prev < threshold && cur >= threshold) {
        events.add(NotificationEvent(
          type: _milestoneType(threshold),
          attendancePercentage: cur,
          previousPercentage: prev,
        ));
      }
    }
    return events;
  }

  /// Evaluate bunk-related conditions.
  ///
  /// Transitions ([previousSafeBunks]) drive safeToBunk / lastSafeBunk /
  /// noSafeBunks. The "missing the next class" conditions are computed from
  /// real present/total hours; the manager deduplicates them per day.
  List<NotificationEvent> evaluateBunks({
    required int safeBunks,
    int? previousSafeBunks,
    required int present,
    required int total,
    double target = 75,
    double dangerThreshold = 60,
  }) {
    final events = <NotificationEvent>[];

    if (previousSafeBunks != null) {
      if (safeBunks == 0 && previousSafeBunks > 0) {
        events.add(NotificationEvent(
          type: NotificationType.noSafeBunks,
          safeBunks: 0,
          previousPercentage: previousSafeBunks.toDouble(),
        ));
      } else if (safeBunks == 1 && previousSafeBunks > 1) {
        events.add(NotificationEvent(
          type: NotificationType.lastSafeBunk,
          safeBunks: 1,
        ));
      } else if (safeBunks > 0 && safeBunks != previousSafeBunks) {
        events.add(NotificationEvent(
          type: NotificationType.safeToBunk,
          safeBunks: safeBunks,
        ));
      }
    }

    if (total <= 0) return events;

    // Percentage if the student skips the next class: present / (total + 1).
    final afterBunk = present / (total + 1) * 100;
    final current = present / total * 100;

    if (current >= dangerThreshold && afterBunk < dangerThreshold) {
      events.add(NotificationEvent(
        type: NotificationType.bunkWouldCauseDanger,
        attendancePercentage: _round(current),
      ));
    } else if (current >= target && afterBunk < target) {
      events.add(NotificationEvent(
        type: NotificationType.bunkWouldCrossSafeThreshold,
        attendancePercentage: _round(current),
      ));
    }

    return events;
  }

  static NotificationType _milestoneType(double threshold) {
    switch (threshold) {
      case 80:
        return NotificationType.reached80;
      case 90:
        return NotificationType.reached90;
      case 95:
        return NotificationType.reached95;
      default:
        return NotificationType.reached80;
    }
  }

  static double _round(double value) {
    return (value * 100).roundToDouble() / 100;
  }
}
