import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/calculations/attendance_engine.dart';
import '../../../models/api/timetable_model.dart';
import '../../../providers/attendance_analysis_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/timetable_provider.dart';
import '../../../features/settings/providers/settings_providers.dart';
import '../application/notification_providers.dart';
import 'providers/notification_settings_provider.dart';

/// App-level notification driver.
///
/// Watches existing app data (attendance analysis + today's timetable) and
/// feeds it to the [NotificationManager]. Owns NO notification logic itself —
/// everything lives in the domain/application layers. Renders nothing.
class NotificationObserver extends ConsumerStatefulWidget {
  const NotificationObserver({super.key});

  @override
  ConsumerState<NotificationObserver> createState() => _NotificationObserverState();
}

class _NotificationObserverState extends ConsumerState<NotificationObserver> {
  Timer? _ticker;
  List<TimetableEntry> _currentSchedule = const [];

  @override
  void initState() {
    super.initState();
    // Exact-alarm permission is needed for precise class reminders.
    Future.microtask(() {
      if (!mounted) return;
      ref.read(localNotificationDatasourceProvider).requestPermissions();
    });
    _ticker = Timer.periodic(const Duration(seconds: 60), (_) => _checkDue());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (previous, next) {
      if (previous?.status == AuthStatus.authenticated &&
          next.status == AuthStatus.unauthenticated) {
        ref.read(notificationManagerProvider).cancelAllScheduled();
      }
    });

    ref.listen(attendanceAnalysisProvider, (_, next) {
      next.whenData((items) => _evaluateAttendance(items));
    });

    ref.listen(todayScheduleProvider, (_, next) {
      next.whenData((entries) {
        _currentSchedule = entries;
        _syncTimetable(entries);
        _checkDue();
      });
    });

    // Zero-size: this widget only observes.
    return const SizedBox.shrink();
  }

  Future<void> _evaluateAttendance(List<AttendanceAnalysisItem> items) async {
    var present = 0;
    var total = 0;
    for (final item in items) {
      present += item.analysis.presentHours;
      total += item.analysis.totalHours;
    }
    if (total <= 0) return;

    final settings = ref.read(notificationSettingsProvider);
    final target = ref.read(attendanceTargetProvider);
    final danger = computeThresholds(target).$1;
    final studentId = await _studentId();
    if (studentId == null || !mounted) return;

    final manager = ref.read(notificationManagerProvider);
    manager.evaluateAttendance(
      present: present,
      total: total,
      studentId: studentId,
      now: DateTime.now(),
      settings: settings,
      target: target,
      dangerThreshold: danger,
    );
    manager.evaluateBunks(
      safeBunks: AttendanceEngine.calculateSafeBunks(present, total),
      present: present,
      total: total,
      studentId: studentId,
      now: DateTime.now(),
      settings: settings,
      target: target,
      dangerThreshold: danger,
    );
  }

  Future<void> _syncTimetable(List<TimetableEntry> entries) async {
    final studentId = await _studentId();
    if (studentId == null || !mounted) return;
    ref.read(notificationManagerProvider).syncTimetable(
          entries: entries,
          studentId: studentId,
          now: DateTime.now(),
          settings: ref.read(notificationSettingsProvider),
        );
  }

  Future<void> _checkDue() async {
    final studentId = await _studentId();
    if (studentId == null || _currentSchedule.isEmpty || !mounted) return;
    ref.read(notificationManagerProvider).checkDueNow(
          entries: _currentSchedule,
          studentId: studentId,
          now: DateTime.now(),
          settings: ref.read(notificationSettingsProvider),
        );
  }

  Future<String?> _studentId() async {
    final session = ref.read(sessionManagerProvider);
    return session.getStudentId();
  }
}
