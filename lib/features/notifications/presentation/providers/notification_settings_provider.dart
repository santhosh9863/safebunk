import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/notifications/notification_providers.dart' show notificationStateStoreProvider;
import '../../application/notification_providers.dart'
    show pulseBackendServiceProvider;
import '../../data/models/notification_preferences_model.dart';

/// Reactive view of notification preferences.
///
/// Only ONE user-facing switch exists: the master [masterEnabled] toggle,
/// which turns every PULSE notification on/off (local + backend). All
/// category flags stay fixed ON; the direct-address gender still syncs from
/// the profile vibe picker.
final notificationSettingsProvider =
    NotifierProvider<NotificationSettings, NotificationPreferences>(
  NotificationSettings.new,
);

class NotificationSettings extends Notifier<NotificationPreferences> {
  @override
  NotificationPreferences build() {
    final store = ref.watch(notificationStateStoreProvider);
    return NotificationPreferences(
      masterEnabled: store.getMasterEnabled(),
      gender: store.getGender(),
    );
  }

  Future<void> setMasterEnabled(bool value) async {
    await ref.read(notificationStateStoreProvider).setMasterEnabled(value);
    state = state.copyWith(masterEnabled: value);
    _syncToBackend();
  }

  /// Pick the direct-address vibe used in messages ('' = auto/neutral).
  Future<void> setGender(String gender) async {
    await ref.read(notificationStateStoreProvider).setGender(gender);
    state = state.copyWith(gender: gender);
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
            bunkEnabled: prefs.bunkEnabled,
            classRemindersEnabled: prefs.classRemindersEnabled,
            milestonesEnabled: prefs.milestonesEnabled,
            timetableEnabled: prefs.timetableEnabled,
            roastingEnabled: prefs.roastingEnabled,
            reminderTimingMinutes: prefs.reminderTiming.minutes,
            gender: prefs.gender,
            wrapUpEnabled: prefs.wrapUpEnabled,
          ),
    );
  }
}
