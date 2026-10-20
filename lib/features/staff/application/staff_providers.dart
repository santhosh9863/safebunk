import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../models/auth/staff_account.dart';
import '../../../models/auth/staff_session.dart';
import '../../../providers/auth_provider.dart';
import '../../notifications/application/notification_providers.dart'
    show pulseBackendServiceProvider;
import '../../reports/data/models/report_model.dart';

/// Staff-assigned report queue (ADMIN receives every report).
final staffReportsProvider = FutureProvider<List<ReportModel>>((ref) async {
  final auth = ref.watch(authProvider);
  final session = _requireStaffSession(ref, auth);

  try {
    return await ref
        .watch(pulseBackendServiceProvider)
        .fetchStaffReports(session.accessToken);
  } on SessionExpiredException {
    unawaited(ref.read(authProvider.notifier).handleSessionExpired());
    rethrow;
  }
});

/// Full report detail plus the staff/admin-visible status and progress history.
final staffReportDetailProvider = FutureProvider.family<ReportModel, String>((
  ref,
  reportId,
) async {
  final auth = ref.watch(authProvider);
  final session = _requireStaffSession(ref, auth);

  try {
    return await ref
        .watch(pulseBackendServiceProvider)
        .fetchStaffReport(session.accessToken, reportId);
  } on SessionExpiredException {
    unawaited(ref.read(authProvider.notifier).handleSessionExpired());
    rethrow;
  }
});

/// Headers for staff-mediated report photo downloads.
final staffReportImageHeadersProvider = FutureProvider<Map<String, String>?>((
  ref,
) async {
  final auth = ref.watch(authProvider);
  final session = auth.staffSession;
  if (!auth.isStaff || session == null) return null;
  return {'Authorization': 'Bearer ${session.accessToken}'};
});

/// Active STAFF accounts only; ADMIN accounts cannot be assignment targets.
final assignableStaffProvider = FutureProvider<List<StaffAccount>>((ref) async {
  final accounts = await ref.watch(staffAccountsProvider.future);
  return accounts
      .where((account) => account.active && account.role == StaffRole.staff)
      .toList(growable: false);
});

/// Admin-only staff account list. The backend enforces the same rule with
/// `RolesGuard`; STAFF must never reach this provider from the UI.
final staffAccountsProvider = FutureProvider<List<StaffAccount>>((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.isAdmin) {
    throw const UnauthorizedException('Administrator access is required.');
  }
  final session = _requireStaffSession(ref, auth);

  try {
    return await ref
        .watch(pulseBackendServiceProvider)
        .fetchStaffAccounts(session.accessToken);
  } on SessionExpiredException {
    unawaited(ref.read(authProvider.notifier).handleSessionExpired());
    rethrow;
  }
});

StaffSession _requireStaffSession(Ref ref, AuthState auth) {
  if (auth.status == AuthStatus.authenticated && !auth.isStaff) {
    // A student session must never be used to call a staff endpoint.
    throw const UnauthorizedException('Staff access is required.');
  }

  final session = auth.staffSession;
  if (session == null || !auth.isStaff) {
    if (auth.status == AuthStatus.authenticated) {
      unawaited(ref.read(authProvider.notifier).handleSessionExpired());
    }
    throw const UnauthorizedException('Staff sign-in required.');
  }
  return session;
}
