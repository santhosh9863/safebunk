import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/auth_provider.dart';
import '../../notifications/application/notification_providers.dart'
    show pulseBackendServiceProvider;
import '../../staff/application/staff_providers.dart';
import '../data/realtime/reports_realtime_client.dart';
import 'reports_providers.dart';

/// The identity and credentials used for the real-time report connection.
///
/// A null value means there is no active student/staff session or the backend
/// is not configured, so the coordinator must stay disconnected.
class ReportsRealtimeIdentity {
  final String baseUrl;
  final String token;
  final String accountKey;
  final bool isStaff;

  const ReportsRealtimeIdentity({
    required this.baseUrl,
    required this.token,
    required this.accountKey,
    required this.isStaff,
  });
}

/// Derives the socket identity from the existing authenticated app session.
/// Student tokens stay in the backend secure store; staff tokens stay in the
/// app's persisted staff session.
final reportsRealtimeIdentityProvider =
    FutureProvider<ReportsRealtimeIdentity?>((ref) async {
      final auth = ref.watch(authProvider);
      if (auth.status != AuthStatus.authenticated) return null;

      final backend = ref.watch(pulseBackendServiceProvider);
      final baseUrl = backend.baseUrl;
      if (baseUrl == null) return null;

      if (auth.isStaff) {
        final session = auth.staffSession;
        if (session == null || session.accessToken.trim().isEmpty) {
          return null;
        }
        return ReportsRealtimeIdentity(
          baseUrl: baseUrl,
          token: session.accessToken,
          accountKey: '${auth.role?.apiValue ?? 'STAFF'}:${session.staffId}',
          isStaff: true,
        );
      }

      final token = await backend.readAccessToken();
      if (token == null) return null;
      return ReportsRealtimeIdentity(
        baseUrl: baseUrl,
        token: token,
        accountKey: 'STUDENT:${auth.username ?? 'restored-session'}',
        isStaff: false,
      );
    });

final reportsRealtimeClientProvider = Provider<ReportsRealtimeClient>((ref) {
  final client = SocketIoReportsRealtimeClient();
  ref.onDispose(client.dispose);
  return client;
});

/// Keeps the socket connection in sync with auth and translates incoming
/// events into targeted Riverpod invalidations. Watched once at the app root.
final reportsRealtimeCoordinatorProvider = Provider<ReportsRealtimeCoordinator>(
  (ref) {
    final client = ref.watch(reportsRealtimeClientProvider);
    final coordinator = ReportsRealtimeCoordinator(ref, client);
    ref.onDispose(coordinator.dispose);
    return coordinator;
  },
);

class ReportsRealtimeCoordinator {
  final Ref _ref;
  final ReportsRealtimeClient _client;

  late final ProviderSubscription<AsyncValue<ReportsRealtimeIdentity?>>
  _identitySubscription;
  late final StreamSubscription<ReportsRealtimeSignal> _signalSubscription;

  ReportsRealtimeIdentity? _identity;
  String? _accountKey;
  bool _hasSeenIdentity = false;
  Timer? _flushTimer;
  final Set<String> _pendingReportIds = <String>{};
  final Set<String> _seenEventIds = <String>{};
  bool _pendingListInvalidation = false;
  bool _disposed = false;
  int _connectionGeneration = 0;

  ReportsRealtimeCoordinator(this._ref, this._client) {
    _signalSubscription = _client.signals.listen(_onSignal);
    _identitySubscription = _ref.listen<AsyncValue<ReportsRealtimeIdentity?>>(
      reportsRealtimeIdentityProvider,
      _onIdentity,
      fireImmediately: true,
    );
  }

  void _onIdentity(
    AsyncValue<ReportsRealtimeIdentity?>? previous,
    AsyncValue<ReportsRealtimeIdentity?> next,
  ) {
    if (_disposed || next.isLoading) return;
    if (next.hasError) {
      _identity = null;
      unawaited(_disconnect());
      return;
    }

    final identity = next.valueOrNull;
    _identity = identity;
    if (identity == null) {
      _accountKey = null;
      unawaited(_disconnect());
      return;
    }

    if (_hasSeenIdentity && _accountKey != identity.accountKey) {
      _resetPendingInvalidations();
      _clearReportCaches();
    }
    _hasSeenIdentity = true;
    _accountKey = identity.accountKey;

    final generation = ++_connectionGeneration;
    unawaited(
      _client
          .connect(baseUrl: identity.baseUrl, token: identity.token)
          .catchError((Object error) {
            if (generation == _connectionGeneration && !_disposed) {
              debugPrint('[Reports realtime] connection failed: $error');
            }
          }),
    );
  }

  Future<void> _disconnect() async {
    _connectionGeneration++;
    _resetPendingInvalidations();
    await _client.disconnect();
  }

  void _resetPendingInvalidations() {
    _pendingReportIds.clear();
    _pendingListInvalidation = false;
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  void _onSignal(ReportsRealtimeSignal signal) {
    if (_disposed) return;

    if (signal is ReportsRealtimeConnected) {
      _resyncFromRest();
      return;
    }

    if (signal is ReportsRealtimeChanged) {
      final event = signal.event;
      if (!_remember(event.eventId)) return;

      _pendingReportIds.add(event.reportId);
      if (event.change != 'progress') {
        _pendingListInvalidation = true;
      }
      _flushTimer ??= Timer(const Duration(milliseconds: 150), _flush);
    }
  }

  /// Prevents a report cache from a previous account being shown after a
  /// student/staff switch. The next connection repopulates the authorized
  /// views through REST.
  void _clearReportCaches() {
    _ref.invalidate(reportsListProvider);
    _ref.invalidate(reportDetailProvider);
    _ref.invalidate(reportImageHeadersProvider);
    _ref.invalidate(staffReportsProvider);
    _ref.invalidate(staffReportDetailProvider);
    _ref.invalidate(staffReportImageHeadersProvider);
  }

  /// A successful connect or reconnect means events may have been missed while
  /// offline. Refetch the authorized lists and any cached detail through REST.
  void _resyncFromRest() {
    _resetPendingInvalidations();

    final identity = _identity;
    if (identity == null) return;
    if (identity.isStaff) {
      _ref.invalidate(staffReportsProvider);
      _ref.invalidate(staffReportDetailProvider);
    } else {
      _ref.invalidate(reportsListProvider);
      _ref.invalidate(reportDetailProvider);
    }
  }

  void _flush() {
    _flushTimer = null;
    if (_disposed) return;

    final identity = _identity;
    if (identity == null) {
      _pendingReportIds.clear();
      _pendingListInvalidation = false;
      return;
    }

    final reportIds = _pendingReportIds.toList(growable: false);
    final refreshList = _pendingListInvalidation;
    _pendingReportIds.clear();
    _pendingListInvalidation = false;

    if (identity.isStaff) {
      if (refreshList) _ref.invalidate(staffReportsProvider);
      for (final id in reportIds) {
        _ref.invalidate(staffReportDetailProvider(id));
      }
    } else {
      if (refreshList) _ref.invalidate(reportsListProvider);
      for (final id in reportIds) {
        _ref.invalidate(reportDetailProvider(id));
      }
    }
  }

  bool _remember(String eventId) {
    if (eventId.trim().isEmpty) return true;
    if (!_seenEventIds.add(eventId)) return false;
    if (_seenEventIds.length > 100) {
      _seenEventIds.remove(_seenEventIds.first);
    }
    return true;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    _identitySubscription.close();
    unawaited(_signalSubscription.cancel());
    unawaited(_client.disconnect());
  }
}
