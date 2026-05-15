import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/network/dio_client.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'services/api/subject_wise_attendance_service.dart';
import 'storage/session_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final sessionStorage = SessionStorage();
  DioClient.init(sessionStorage: sessionStorage);

  // TEMP: Isolated subject-wise API test
  _testSubjectWiseApi();

  runApp(
    ProviderScope(
      overrides: [
        sessionStorageProvider.overrideWithValue(sessionStorage),
      ],
      child: const SafeBunkApp(),
    ),
  );
}

class SafeBunkApp extends ConsumerWidget {
  const SafeBunkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SafeBunk V2',
      theme: AppTheme.lightTheme,
      home: switch (authState.status) {
        AuthStatus.unknown => const Scaffold(body: Center(child: CircularProgressIndicator())),
        AuthStatus.authenticated => const DashboardScreen(),
        AuthStatus.unauthenticated => const LoginScreen(),
      },
    );
  }
}

// TEMP: Isolated subject-wise API test. Remove after verification.
void _testSubjectWiseApi() async {
  try {
    final sessionStorage = SessionStorage();
    final studentId = (await sessionStorage.getStudentId()) ?? '4286';
    final service = SubjectWiseAttendanceService();
    await service.fetchSubjectWiseAttendance(studentId: studentId);
  } catch (e) {
    // print('[SUBJECT_API] Test error: $e');
  }
}
