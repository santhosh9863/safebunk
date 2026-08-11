import '../entities/notification_event.dart';
import '../entities/notification_message.dart';
import '../enums/notification_type.dart';

/// Turns a [NotificationEvent] (data only) into a user-facing
/// [NotificationMessage].
///
/// Wording is centralized HERE — no notification text lives in providers,
/// widgets or repositories. Every placeholder is filled from verified event
/// data; nothing is invented.
///
/// When [roasting] is disabled the same information is delivered with neutral
/// wording.
class NotificationContentService {
  const NotificationContentService();

  NotificationMessage build(
    NotificationEvent event, {
    required bool roasting,
  }) {
    final template = roasting ? _roast(event.type) : _neutral(event.type);
    return NotificationMessage(
      title: _fill(template.title, event),
      body: _fill(template.body, event),
    );
  }

  String _fill(String template, NotificationEvent event) {
    final metadata = event.metadata;

    final formattedPct = event.attendancePercentage?.toStringAsFixed(1) ?? '0.0';
    final subject = _subjectName(event);

    var result = template
        .replaceAll('{percentage}', formattedPct)
        .replaceAll('{subjectName}', subject)
        .replaceAll('{facultyName}', (metadata['facultyName'] as String?) ?? subject);

    for (final entry in metadata.entries) {
      if (entry.value is String || entry.value is num) {
        result = result.replaceAll('{${entry.key}}', entry.value.toString());
      }
    }
    return result;
  }

  String _subjectName(NotificationEvent event) {
    final raw = event.subjectName;
    if (raw == null || raw.trim().isEmpty) return 'this class';
    return raw.replaceFirst(RegExp(r'\s*\([^)]*\)$'), '').trim();
  }

  // ─────────────────────────────────────────────────────────────
  // Message library
  // ─────────────────────────────────────────────────────────────

  static _Template _roast(NotificationType type) {
    switch (type) {
      // ── Attendance ──
      case NotificationType.attendanceDropped:
        return const _Template("She's losing interest. 👀", 'Your attendance dropped to {percentage}%.');
      case NotificationType.enteredWarningZone:
        return const _Template('We need to talk. 👀', '{subjectName} is now at {percentage}%.');
      case NotificationType.enteredDangerZone:
        return const _Template("You're cooked. 😭", '{subjectName} has dropped below the safe zone.');
      case NotificationType.leftSafeZone:
        return const _Template('That hurt. 📉', 'You dropped below 75% attendance.');
      case NotificationType.attendanceImproved:
        return const _Template('She noticed. 👀', 'Your attendance improved to {percentage}%.');
      case NotificationType.enteredSafeZone:
        return const _Template('Back together. 🫶', "You're back above the 75% safe zone.");
      case NotificationType.recoveredFromDanger:
        return const _Template('Character development. 🔥', 'You recovered from the danger zone.');
      case NotificationType.perfectAttendance:
        return const _Template('Too available. 🗿', '100% attendance. Bro practically lives on campus.');

      // ── Bunking ──
      case NotificationType.safeToBunk:
        return const _Template('Nice try. 😏', 'You can safely miss this class.');
      case NotificationType.lastSafeBunk:
        return const _Template('One last time. 💀', 'This is your final safe bunk.');
      case NotificationType.noSafeBunks:
        return const _Template('No more games. 🚫', 'You have zero safe leaves left.');
      case NotificationType.bunkWouldCauseDanger:
        return const _Template('Choose wisely. 👀', 'Missing this class could put you in the danger zone.');
      case NotificationType.bunkWouldCrossSafeThreshold:
        return const _Template('Not this time. 💀', 'Missing this class will take you below 75%.');

      // ── Class / Timetable ──
      case NotificationType.classReminder30Min:
        return const _Template('Time to move. ⏰', '{subjectName} starts in 30 minutes.');
      case NotificationType.classReminder10Min:
        return const _Template("She's waiting. 👀", '{subjectName} starts in 10 minutes.');
      case NotificationType.classReminder5Min:
        return const _Template("Don't ghost her. 💀", '{subjectName} starts in 5 minutes.');
      case NotificationType.classStarting:
        return const _Template('Move, bro. 😭', '{subjectName} is starting now.');
      case NotificationType.classMissed:
        return const _Template('Left her waiting. 💀', 'You missed {subjectName}.');
      case NotificationType.nextClass:
        return const _Template('Round two. 😏', '{subjectName} starts in {minutes} minutes.');
      case NotificationType.heavyClassDay:
        return const _Template('No escape today. 💀', 'You have {classCount} classes scheduled today.');
      case NotificationType.lightClassDay:
        return const _Template("She's being nice. 😌", 'Only {classCount} classes are scheduled today.');
      case NotificationType.earlyClass:
        return const _Template('At this hour? 😭', 'Your first class starts at {time}.');
      case NotificationType.longClassGap:
        return const _Template('Private time. 👀', 'You have a {duration} gap before your next class.');
      case NotificationType.noClasses:
        return const _Template('Finally free. 🗿', 'You have no classes scheduled today.');

      // ── Milestones ──
      case NotificationType.reached75:
        return const _Template("We're alive. 🫡", 'You just crossed the 75% safe zone.');
      case NotificationType.reached80:
        return const _Template('Showing off now. 💀', 'Your attendance just crossed 80%.');
      case NotificationType.reached90:
        return const _Template('Too consistent. 😭', 'Your attendance just crossed 90%.');
      case NotificationType.reached95:
        return const _Template('Doing too much. 😭', "You're sitting at 95% attendance.");
      case NotificationType.reached100:
        return const _Template('Touch grass. 🗿', 'You somehow reached 100% attendance.');

      // ── System ──
      case NotificationType.syncSuccess:
        return const _Template('Synced. 💅', 'Attendance is up to date.');
      case NotificationType.syncFailure:
        return const _Template('Rip. 📡', 'Could not sync attendance. Try again later.');
      case NotificationType.offline:
        return const _Template('No signal. 📵', "You're offline — check your connection.");
      case NotificationType.timetableUpdated:
        return const _Template('New schedule. 🗓️', 'Your timetable has been updated.');
    }
  }

  static _Template _neutral(NotificationType type) {
    switch (type) {
      case NotificationType.attendanceDropped:
        return const _Template('Attendance dropped', 'Your attendance dropped to {percentage}%.');
      case NotificationType.enteredWarningZone:
        return const _Template('Attendance warning', '{subjectName} is now at {percentage}%.');
      case NotificationType.enteredDangerZone:
        return const _Template('Attendance danger', '{subjectName} has dropped below the safe zone.');
      case NotificationType.leftSafeZone:
        return const _Template('Below safe zone', 'You dropped below 75% attendance.');
      case NotificationType.attendanceImproved:
        return const _Template('Attendance improved', 'Your attendance improved to {percentage}%.');
      case NotificationType.enteredSafeZone:
        return const _Template('Back to safe zone', "You're back above the 75% safe zone.");
      case NotificationType.recoveredFromDanger:
        return const _Template('Recovered', 'You recovered from the danger zone.');
      case NotificationType.perfectAttendance:
        return const _Template('Perfect attendance', 'Your attendance is at 100%.');

      case NotificationType.safeToBunk:
        return const _Template('Safe to skip', 'You can safely miss this class.');
      case NotificationType.lastSafeBunk:
        return const _Template('Last safe leave', 'This is your final safe bunk.');
      case NotificationType.noSafeBunks:
        return const _Template('No safe leaves', 'You have zero safe leaves left.');
      case NotificationType.bunkWouldCauseDanger:
        return const _Template('Attendance risk', 'Missing this class could put you in the danger zone.');
      case NotificationType.bunkWouldCrossSafeThreshold:
        return const _Template('Below 75% risk', 'Missing this class will take you below 75%.');

      case NotificationType.classReminder30Min:
        return const _Template('Class in 30 minutes', '{subjectName} starts in 30 minutes.');
      case NotificationType.classReminder10Min:
        return const _Template('Class in 10 minutes', '{subjectName} starts in 10 minutes.');
      case NotificationType.classReminder5Min:
        return const _Template('Class in 5 minutes', '{subjectName} starts in 5 minutes.');
      case NotificationType.classStarting:
        return const _Template('Class starting', '{subjectName} is starting now.');
      case NotificationType.classMissed:
        return const _Template('Class missed', 'You missed {subjectName}.');
      case NotificationType.nextClass:
        return const _Template('Next class', '{subjectName} starts in {minutes} minutes.');
      case NotificationType.heavyClassDay:
        return const _Template('Full day', 'You have {classCount} classes scheduled today.');
      case NotificationType.lightClassDay:
        return const _Template('Light day', 'Only {classCount} classes are scheduled today.');
      case NotificationType.earlyClass:
        return const _Template('Early start', 'Your first class starts at {time}.');
      case NotificationType.longClassGap:
        return const _Template('Long gap', 'You have a {duration} gap before your next class.');
      case NotificationType.noClasses:
        return const _Template('No classes', 'You have no classes scheduled today.');

      case NotificationType.reached75:
        return const _Template('Safe zone reached', 'You just crossed the 75% safe zone.');
      case NotificationType.reached80:
        return const _Template('80% reached', 'Your attendance just crossed 80%.');
      case NotificationType.reached90:
        return const _Template('90% reached', 'Your attendance just crossed 90%.');
      case NotificationType.reached95:
        return const _Template('95% reached', "You're sitting at 95% attendance.");
      case NotificationType.reached100:
        return const _Template('100% reached', 'You somehow reached 100% attendance.');

      case NotificationType.syncSuccess:
        return const _Template('Attendance synced', 'Attendance is up to date.');
      case NotificationType.syncFailure:
        return const _Template('Sync failed', 'Could not sync attendance. Try again later.');
      case NotificationType.offline:
        return const _Template('Offline', "You're offline — check your connection.");
      case NotificationType.timetableUpdated:
        return const _Template('Timetable updated', 'Your timetable has been updated.');
    }
  }
}

class _Template {
  final String title;
  final String body;

  const _Template(this.title, this.body);
}
