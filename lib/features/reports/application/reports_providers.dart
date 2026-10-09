import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notifications/application/notification_providers.dart'
    show pulseBackendServiceProvider;
import '../data/models/report_model.dart';
import '../data/repositories/reports_repository.dart';
import '../domain/report_enums.dart';

/// Reports reuse the shared authenticated PULSE backend client already used by
/// the notification sync (same secure-stored Bearer token, same Dio).
final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository(ref.watch(pulseBackendServiceProvider));
});

/// Whether the PULSE backend URL is configured for this build.
final reportsBackendEnabledProvider = Provider<bool>((ref) {
  return ref.watch(reportsRepositoryProvider).isEnabled;
});

/// The authenticated student's reports (newest first), fetched from the backend.
/// Invalidate this after creating a report or on pull-to-refresh.
final reportsListProvider = FutureProvider<List<ReportModel>>((ref) async {
  return ref.watch(reportsRepositoryProvider).listMyReports();
});

/// Client-side status filter for "My Reports" (backend Phase 1 has no filter
/// query params). `null` = all statuses.
final reportStatusFilterProvider = StateProvider<ReportStatus?>((ref) => null);

/// A single owned report, keyed by id. Cross-student access surfaces as an
/// error (backend returns 404 with the same shape as a missing report).
final reportDetailProvider =
    FutureProvider.family<ReportModel, String>((ref, id) async {
  return ref.watch(reportsRepositoryProvider).getReport(id);
});

/// Bearer headers used to fetch an authenticated attachment image. Null when
/// the backend is disabled or the session token is missing.
final reportImageHeadersProvider = FutureProvider<Map<String, String>?>((ref) {
  return ref.watch(reportsRepositoryProvider).imageAuthHeaders();
});

/// Derived list with the active status filter applied. Pure flutter-side
/// transformation so filtering is instant and does not refetch.
final filteredReportsProvider = Provider<AsyncValue<List<ReportModel>>>((ref) {
  final reports = ref.watch(reportsListProvider);
  final filter = ref.watch(reportStatusFilterProvider);
  return reports.whenData((list) {
    if (filter == null) return list;
    return list.where((r) => r.statusEnum == filter).toList(growable: false);
  });
});
