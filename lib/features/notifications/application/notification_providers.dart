import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_providers.dart' show notificationServiceProvider, notificationStateStoreProvider;
import '../../../services/api/pulse_backend_service.dart';
import '../data/datasources/local_notification_datasource.dart';
import '../data/repositories/notification_repository_impl.dart';
import '../domain/services/notification_content_service.dart';
import '../domain/services/notification_rule_engine.dart';
import 'notification_manager.dart';
import 'notification_scheduler.dart';

/// Current FCM device token (set by the auth flow; null until obtained).
final deviceTokenProvider = StateProvider<String?>((ref) => null);

/// Client for the PULSE backend (push registration + preferences sync).
final pulseBackendServiceProvider = Provider<PulseBackendService>((ref) {
  return PulseBackendService();
});

/// Repository for notification persistence (baselines + dedup markers).
final notificationRepositoryProvider = Provider<NotificationRepositoryImpl>((ref) {
  return NotificationRepositoryImpl(ref.watch(notificationStateStoreProvider));
});

/// Delivery port. Falls back to a no-op implementation when the real service
/// is unavailable so the pipeline never needs null checks.
final localNotificationDatasourceProvider = Provider<LocalNotificationDatasource>((ref) {
  final service = ref.watch(notificationServiceProvider);
  if (service == null) return const NoopNotificationDatasource();
  return AndroidLocalNotificationDatasource(service);
});

final notificationRuleEngineProvider = Provider<NotificationRuleEngine>((ref) {
  return const NotificationRuleEngine();
});

final notificationContentServiceProvider = Provider<NotificationContentService>((ref) {
  return const NotificationContentService();
});

final notificationSchedulerProvider = Provider<ClassReminderScheduler>((ref) {
  return const ClassReminderScheduler();
});

/// Application-layer orchestrator consumed by the NotificationObserver.
final notificationManagerProvider = Provider<NotificationManager>((ref) {
  return NotificationManager(
    engine: ref.watch(notificationRuleEngineProvider),
    contentService: ref.watch(notificationContentServiceProvider),
    scheduler: ref.watch(notificationSchedulerProvider),
    datasource: ref.watch(localNotificationDatasourceProvider),
    repository: ref.watch(notificationRepositoryProvider),
    backend: ref.watch(pulseBackendServiceProvider),
  );
});
