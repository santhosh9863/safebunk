import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safebunk_shared/safebunk_shared.dart';
import 'features/login/login_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'theme/app_theme.dart';

final authStateProvider = Provider<AsyncValue<bool>>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  return AsyncValue.data(authRepo.isAuthenticated);
});

class PULSEWebApp extends ConsumerWidget {
  const PULSEWebApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'PULSE',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authRepo = ref.watch(authRepositoryProvider);
    final isAuth = authRepo.isAuthenticated;

    if (isAuth) {
      return const DashboardScreen();
    }

    return const LoginScreen();
  }
}
