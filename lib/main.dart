import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/cache/persistent_cache.dart';
import 'firebase_options.dart';
import 'core/network/dio_client.dart';
import 'core/notifications/notification_providers.dart';
import 'core/notifications/notification_service.dart';
import 'core/notifications/notification_state_store.dart';
import 'core/session/session_manager.dart';
import 'core/storage/secure_storage_service.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/providers/settings_providers.dart';
import 'providers/auth_provider.dart';
import 'screens/web_login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await PersistentCache.init();

  final notificationStore = NotificationStateStore();
  await notificationStore.init();

  NotificationService? notificationService;
  try {
    notificationService = await NotificationService.create();
    await notificationService.requestPermission();
  } catch (e) {
    debugPrint('[Notifications] Init failed (non-fatal): $e');
  }

  final secureStorage = SecureStorageService();
  final sessionManager = SessionManager(secureStorage);
  DioClient.init(sessionManager: sessionManager);

  runApp(
    ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(secureStorage),
        notificationStateStoreProvider.overrideWithValue(notificationStore),
        if (notificationService != null)
          notificationServiceProvider.overrideWithValue(notificationService),
      ],
      child: const SafeBunkApp(),
    ),
  );
}

class SafeBunkApp extends ConsumerWidget {
  const SafeBunkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final darkMode = ref.watch(darkModeProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PULSE',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      home: const WebLoginScreen(),
    );
  }
}
