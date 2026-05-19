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
import 'providers/update_provider.dart';
import 'services/analytics_service.dart';
import 'services/update_service.dart';
import 'shared/widgets/update_dialog.dart';
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

  final toggles = <Override>{
    secureStorageProvider.overrideWithValue(secureStorage),
    notificationStateStoreProvider.overrideWithValue(notificationStore),
    if (notificationService != null)
      notificationServiceProvider.overrideWithValue(notificationService),
  };

  if (notificationService != null) {
    notificationService.onNotificationTap = (payload) {
      // Navigation handled by main_shell_screen; just bring app to foreground
    };
  }

  runApp(
    ProviderScope(
      overrides: [
        ...toggles,
        attendanceAlertsProvider.overrideWith(
          (ref) => notificationStore.getToggleAttendanceAlerts(),
        ),
        lowAttendanceWarningProvider.overrideWith(
          (ref) => notificationStore.getToggleLowAttendanceWarning(),
        ),
        dailyReminderProvider.overrideWith(
          (ref) => notificationStore.getToggleDailyReminder(),
        ),
        weeklySummaryProvider.overrideWith(
          (ref) => notificationStore.getToggleWeeklySummary(),
        ),
      ],
      child: const SafeBunkApp(),
    ),
  );
}

class SafeBunkApp extends ConsumerStatefulWidget {
  const SafeBunkApp({super.key});

  @override
  ConsumerState<SafeBunkApp> createState() => _SafeBunkAppState();
}

class _SafeBunkAppState extends ConsumerState<SafeBunkApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _hasShownUpdateDialog = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      AnalyticsService.logAppOpen();
      ref.read(updateProvider.notifier).checkForUpdate();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(updateProvider, (previous, next) {
      if (next.status == UpdateStatus.updateAvailable &&
          next.info != null &&
          !_hasShownUpdateDialog) {
        _hasShownUpdateDialog = true;
        debugPrint('[UpdateService] Update popup shown: ${next.type} update to ${next.info!.latestVersion}');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _navigatorKey.currentContext != null) {
            showDialog(
              context: _navigatorKey.currentContext!,
              barrierDismissible: next.type != UpdateType.required,
              builder: (_) => UpdateDialog(
                info: next.info!,
                updateType: next.type,
              ),
            );
          }
        });
      }
    });

    final darkMode = ref.watch(darkModeProvider);

    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'PULSE',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      home: const WebLoginScreen(),
    );
  }
}
