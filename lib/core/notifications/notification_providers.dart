import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notification_service.dart';
import 'notification_state_store.dart';

final notificationStateStoreProvider = Provider<NotificationStateStore>((ref) {
  return NotificationStateStore();
});

final notificationServiceProvider = Provider<NotificationService?>((ref) {
  return null;
});
