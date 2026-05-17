import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notification_scheduler.dart';
import 'notification_service.dart';
import 'notification_state_store.dart';

final notificationStateStoreProvider = Provider<NotificationStateStore>((ref) {
  return NotificationStateStore();
});

final notificationServiceProvider = Provider<NotificationService?>((ref) {
  return null;
});

final notificationSchedulerProvider = Provider<NotificationScheduler?>((ref) {
  final service = ref.watch(notificationServiceProvider);
  final store = ref.watch(notificationStateStoreProvider);
  if (service == null) return null;
  return NotificationScheduler(service: service, store: store);
});
