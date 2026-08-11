import 'package:riverpod/riverpod.dart';
import '../models/analytics/analytics.dart';
import '../repositories/analytics_repository.dart';

final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  throw UnimplementedError('analyticsRepositoryProvider must be overridden');
});

final analyticsProvider = FutureProvider<ConsolidatedAnalytics>((ref) async {
  final repo = ref.watch(analyticsRepositoryProvider);
  return repo.getAnalytics();
});

final hourWiseAttendanceProvider = FutureProvider<List<HourWiseAttendance>>((ref) async {
  final repo = ref.watch(analyticsRepositoryProvider);
  return repo.getHourWiseAttendance();
});
