import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/cache/persistent_cache.dart';
import 'core/network/dio_client.dart';
import 'core/session/session_manager.dart';
import 'core/storage/secure_storage_service.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/providers/settings_providers.dart';
import 'providers/auth_provider.dart';
import 'screens/web_login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await PersistentCache.init();

  final secureStorage = SecureStorageService();
  final sessionManager = SessionManager(secureStorage);
  DioClient.init(sessionManager: sessionManager);

  runApp(
    ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(secureStorage),
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
      title: 'SafeBunk V2',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      home: const WebLoginScreen(),
    );
  }
}
