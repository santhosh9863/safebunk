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
import 'features/notifications/application/fcm_setup.dart';
import 'providers/auth_provider.dart';
import 'providers/update_provider.dart';
import 'services/analytics_service.dart';
import 'services/update_service.dart';
import 'shared/widgets/update_dialog.dart';
import 'screens/web_login_screen.dart';
import 'screens/main_shell_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

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

  // FCM: captures the token, forwards foreground messages into the local
  // notification pipeline. Registration with the backend happens after login.
  await FcmController.initialize(notificationService);

  final secureStorage = SecureStorageService();
  final sessionManager = SessionManager(secureStorage);
  DioClient.init(sessionManager: sessionManager);

  final toggles = <Override>{
    secureStorageProvider.overrideWithValue(secureStorage),
    notificationStateStoreProvider.overrideWithValue(notificationStore),
    if (notificationService != null)
      notificationServiceProvider.overrideWithValue(notificationService),
  };

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
  bool _hasShownUpdateDialog = false;

  @override
  void initState() {
    super.initState();

    // Notification taps (local + FCM background/terminated) bring the user
    // back to the dashboard when a session is active. If no session exists
    // yet the login screen's restore flow handles navigation on its own.
    Future<void> handleNotificationOpen() async {
      final auth = ref.read(authProvider);
      if (auth.status != AuthStatus.authenticated) return;
      final context = rootNavigatorKey.currentContext;
      if (context == null) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShellScreen()),
        (route) => false,
      );
    }

    FcmController.onMessageOpened = (type, eventId) => handleNotificationOpen();
    ref.read(notificationServiceProvider)?.onNotificationTap = (_) =>
        handleNotificationOpen();

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
          if (mounted && rootNavigatorKey.currentContext != null) {
            showDialog(
              context: rootNavigatorKey.currentContext!,
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
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'PULSE',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      home: const WebLoginScreen(),
    );
  }
}
