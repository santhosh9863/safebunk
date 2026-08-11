import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safebunk_shared/safebunk_shared.dart';
import '../api/http_client.dart';
import '../storage/web_storage.dart';
import '../../repositories/web_auth_repository.dart';
import '../../repositories/web_profile_repository.dart';
import '../../repositories/web_attendance_repository.dart';
import '../../repositories/web_timetable_repository.dart';
import '../../repositories/web_analytics_repository.dart';

final initialTokenProvider = FutureProvider<String?>((ref) async {
  return WebStorage.getAccessToken();
});

final httpClientProvider = Provider<HttpClient>((ref) {
  final client = HttpClient();
  final token = ref.watch(initialTokenProvider).valueOrNull;
  if (token != null) {
    client.setAccessToken(token);
  }
  return client;
});

List<Override> get appOverrides {
  return [
    authRepositoryProvider.overrideWith((ref) {
      return WebAuthRepository(ref.watch(httpClientProvider));
    }),
    profileRepositoryProvider.overrideWith((ref) {
      return WebProfileRepository(ref.watch(httpClientProvider));
    }),
    attendanceRepositoryProvider.overrideWith((ref) {
      return WebAttendanceRepository(ref.watch(httpClientProvider));
    }),
    timetableRepositoryProvider.overrideWith((ref) {
      return WebTimetableRepository(ref.watch(httpClientProvider));
    }),
    analyticsRepositoryProvider.overrideWith((ref) {
      return WebAnalyticsRepository(ref.watch(httpClientProvider));
    }),
  ];
}
