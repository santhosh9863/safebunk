import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/notifications/notification_providers.dart' show notificationStateStoreProvider;
import '../../../../features/settings/providers/settings_providers.dart'
    show attendanceAlertsProvider, lowAttendanceWarningProvider;
import '../../application/notification_providers.dart'
    show pulseBackendServiceProvider;
import '../../data/models/notification_preferences_model.dart';

/// Reactive view of all notification preferences.
///
/// `attendanceEnabled` and `bunkEnabled` are driven by the EXISTING settings
/// toggles (written directly as StateProviders by the settings UI, per the
/// existing behavior). The new product toggles (master, class reminders,
/// milestones, roasting, reminder timing) persist in the notification state
/// store and are written through this notifier.
final notificationSettingsProvider =
    NotifierProvider<NotificationSettings, NotificationPreferences>(
  NotificationSettings.new,
);

class NotificationSettings extends Notifier<NotificationPreferences> {
  @override
  NotificationPreferences build() {
    ref.watch(attendanceAlertsProvider);
    ref.watch(lowAttendanceWarningProvider);
    final store = ref.watch(notificationStateStoreProvider);
    return NotificationPreferences(
      masterEnabled: store.getMasterEnabled(),
      attendanceEnabled: ref.read(attendanceAlertsProvider),
      bunkEnabled: ref.read(lowAttendanceWarningProvider),
      classRemindersEnabled: store.getClassRemindersEnabled(),
      milestonesEnabled: store.getMilestonesEnabled(),
      roastingEnabled: store.getRoastingEnabled(),
      reminderTiming: _timingFromMinutes(store.getReminderTimingMinutes()),
    );
  }

  Future<void> setMasterEnabled(bool value) async {
    await ref.read(notificationStateStoreProvider).setMasterEnabled(value);
    state = state.copyWith(masterEnabled: value);
    _syncToBackend();
  }

  Future<void> setClassRemindersEnabled(bool value) async {
    await ref.read(notificationStateStoreProvider).setClassRemindersEnabled(value);
    state = state.copyWith(classRemindersEnabled: value);
    _syncToBackend();
  }

  Future<void> setMilestonesEnabled(bool value) async {
    await ref.read(notificationStateStoreProvider).setMilestonesEnabled(value);
    state = state.copyWith(milestonesEnabled: value);
    _syncToBackend();
  }

  Future<void> setRoastingEnabled(bool value) async {
    await ref.read(notificationStateStoreProvider).setRoastingEnabled(value);
    state = state.copyWith(roastingEnabled: value);
    _syncToBackend();
  }

  Future<void> setReminderTiming(ClassReminderTiming timing) async {
    await ref
        .read(notificationStateStoreProvider)
        .setReminderTimingMinutes(timing.minutes);
    state = state.copyWith(reminderTiming: timing);
    _syncToBackend();
  }

  /// Mirror the current preferences to the PULSE backend (best-effort).
  void _syncToBackend() {
    final prefs = state;
    unawaited(
      ref
          .read(pulseBackendServiceProvider)
          .updatePreferences(
            masterEnabled: prefs.masterEnabled,
            attendanceEnabled: prefs.attendanceEnabled,
            classRemindersEnabled: prefs.classRemindersEnabled,
            milestonesEnabled: prefs.milestonesEnabled,
            roastingEnabled: prefs.roastingEnabled,
            reminderTimingMinutes: prefs.reminderTiming.minutes,
          ),
    );
  }

  static ClassReminderTiming _timingFromMinutes(int minutes) {
    switch (minutes) {
      case 30:
        return ClassReminderTiming.minutes30;
      case 5:
        return ClassReminderTiming.minutes5;
      default:
        return ClassReminderTiming.minutes10;
    }
  }
}
