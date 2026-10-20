import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/cache/cache_manager.dart';
import '../core/cache/persistent_cache.dart';
import '../core/errors/app_exceptions.dart';
import '../core/network/dio_client.dart';
import '../core/notifications/notification_providers.dart';
import '../core/session/session_manager.dart';
import '../core/storage/secure_storage_service.dart';
import '../features/notifications/application/fcm_setup.dart';
import '../features/notifications/application/notification_providers.dart';
import '../features/notifications/presentation/providers/notification_settings_provider.dart';
import '../models/auth/staff_session.dart';
import '../services/api/auth_api_service.dart';
import '../services/repositories/auth_repository.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// The identity type of the active session.
///
/// Student sessions come from Linways; staff/admin sessions come from the
/// PULSE backend's local `StaffUser` table. The role is only ever assigned from
/// the backend response or the securely stored session created from one.
enum AuthRole {
  student('STUDENT'),
  staff('STAFF'),
  admin('ADMIN');

  const AuthRole(this.apiValue);

  final String apiValue;

  bool get isStaff => this == staff || this == admin;
  bool get isAdmin => this == admin;

  static AuthRole fromStaffRole(StaffRole role) {
    return switch (role) {
      StaffRole.staff => AuthRole.staff,
      StaffRole.admin => AuthRole.admin,
    };
  }
}

class AuthState {
  final AuthStatus status;
  final String? error;
  final bool isLoading;
  final String? username;
  final AuthRole? role;
  final StaffSession? staffSession;

  const AuthState({
    required this.status,
    this.error,
    this.isLoading = false,
    this.username,
    this.role,
    this.staffSession,
  });

  static const unknown = AuthState(status: AuthStatus.unknown);
  static const authenticated = AuthState(
    status: AuthStatus.authenticated,
    role: AuthRole.student,
  );
  static const unauthenticated = AuthState(status: AuthStatus.unauthenticated);

  bool get isStaff => role?.isStaff ?? false;
  bool get isAdmin => role == AuthRole.admin;

  AuthState copyWith({
    AuthStatus? status,
    String? error,
    bool? isLoading,
    String? username,
    AuthRole? role,
    StaffSession? staffSession,
    bool clearStaffSession = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      error: error,
      isLoading: isLoading ?? this.isLoading,
      username: username ?? this.username,
      role: role ?? this.role,
      staffSession: clearStaffSession
          ? null
          : staffSession ?? this.staffSession,
    );
  }
}

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final sessionManagerProvider = Provider<SessionManager>((ref) {
  final secureStorage = ref.watch(secureStorageProvider);
  return SessionManager(secureStorage);
});

final authApiServiceProvider = Provider<AuthApiService>((ref) {
  return AuthApiService(DioClient.instance.dio);
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final authApiService = ref.watch(authApiServiceProvider);
  final sessionManager = ref.watch(sessionManagerProvider);
  return AuthRepository(
    authApiService: authApiService,
    sessionManager: sessionManager,
  );
});

final cacheManagerProvider = Provider<CacheManager>((ref) {
  final manager = CacheManager();
  manager.registerAsync(PersistentCache.clearAll);
  return manager;
});

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  final sessionManager = ref.watch(sessionManagerProvider);
  final cacheManager = ref.watch(cacheManagerProvider);
  final notifier = AuthNotifier(
    authRepository,
    sessionManager,
    cacheManager,
    ref,
  );
  DioClient.sessionExpiredHandler = () => notifier.handleSessionExpired();
  return notifier;
});

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _authRepository;
  final SessionManager _sessionManager;
  final CacheManager _cacheManager;
  final Ref _ref;
  bool _handlingSessionExpiry = false;

  AuthNotifier(
    this._authRepository,
    this._sessionManager,
    this._cacheManager,
    this._ref,
  ) : super(const AuthState(status: AuthStatus.unknown)) {
    _checkSession();
  }

  Future<void> _checkSession() async {
    try {
      // Staff and student sessions are mutually exclusive. Restore the staff
      // session first because it is the only identity allowed into staff
      // screens; a stale student cookie must never take precedence.
      final staffSession = await _sessionManager.restoreStaffSession();
      if (staffSession != null) {
        await _sessionManager.clearSession();
        state = AuthState(
          status: AuthStatus.authenticated,
          username: staffSession.username,
          role: AuthRole.fromStaffRole(staffSession.role),
          staffSession: staffSession,
        );
        return;
      }

      final session = await _sessionManager.restoreSession();
      final hasSession = session != null;
      final username = session?.username;

      if (hasSession) {
        await _sessionManager.clearStaffSession();
      }

      state = AuthState(
        status: hasSession
            ? AuthStatus.authenticated
            : AuthStatus.unauthenticated,
        username: username,
        role: hasSession ? AuthRole.student : null,
      );

      // Re-attach the device to the backend with the stored backend session
      // (it survives restarts in its own secure storage).
      if (hasSession) {
        unawaited(_syncPushRegistration());
      }
    } catch (_) {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  /// Registers this device's FCM token when a PULSE backend session already
  /// exists. Runs after fresh login and after restoring the Linways session.
  Future<void> _syncPushRegistration() async {
    try {
      final backend = _ref.read(pulseBackendServiceProvider);
      // No backend session (restore-only path): only a fresh login can
      // re-authenticate the backend because the password is never stored.
      if (!backend.isEnabled || !await backend.isLoggedIn) return;

      final token = await FcmController.refreshToken();
      _ref.read(deviceTokenProvider.notifier).state = token;
      if (token == null) return;
      await backend.registerDevice(token);

      FcmController.attachTokenRefreshListener((newToken) async {
        _ref.read(deviceTokenProvider.notifier).state = newToken;
        if (await backend.isLoggedIn) {
          await backend.registerDevice(newToken);
        }
      });
    } catch (e) {
      debugPrint('[PULSE backend] push registration sync failed: $e');
    }
  }

  /// Establishes the PULSE backend session with the same credentials used for
  /// the Linways login. This is awaited during login so Reports never races a
  /// background request that has not stored its token yet.
  Future<bool> _establishBackendSession(
    String username,
    String password,
  ) async {
    final backend = _ref.read(pulseBackendServiceProvider);
    if (!backend.isEnabled) return false;
    try {
      final ok = await backend.login(username, password);
      if (!ok) {
        debugPrint(
          '[PULSE backend] session establishment failed; Reports will ask for login again.',
        );
      }
      return ok;
    } catch (e) {
      debugPrint('[PULSE backend] session establishment error: $e');
      return false;
    }
  }

  /// Non-critical post-login sync: FCM device registration and the detected
  /// gender preference. Failures here never block attendance or login.
  Future<void> _syncAfterBackendLogin() async {
    await _syncPushRegistration();
    try {
      final backend = _ref.read(pulseBackendServiceProvider);
      if (!backend.isEnabled) return;

      // Auto-fill the message vibe from the gender Linways provides — but
      // never override a choice the user already made in the profile.
      final detected = await backend.getDetectedGender();
      if (detected.isNotEmpty) {
        final settings = _ref.read(notificationSettingsProvider);
        if (settings.gender.isEmpty) {
          await _ref
              .read(notificationSettingsProvider.notifier)
              .setGender(detected);
        }
      }
    } catch (e) {
      debugPrint('[PULSE backend] post-login profile sync failed: $e');
    }
  }

  /// Unregister the device token and invalidate the backend student session.
  Future<void> _clearPushRegistration() async {
    _ref.read(deviceTokenProvider.notifier).state = null;
    final backend = _ref.read(pulseBackendServiceProvider);
    if (!backend.isEnabled) return;
    if (await backend.isLoggedIn) {
      final token = await FcmController.refreshToken();
      if (token != null) {
        await backend.unregisterDevice(token);
      }
    }
    // Always clear persisted backend credentials, including a stale/expired
    // token that is no longer considered logged in.
    await backend.logout();
  }

  Future<void> login(String username, String password) async {
    if (state.isLoading) return;
    final previousStaff = state.staffSession;
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _authRepository.login(username, password);
      debugPrint('[AccountSwitch] login(): session saved for "$username"');
      // Guarantee the next dashboard load is fetched live from Linways:
      // wipe memory + persisted (Hive) caches so no previous account's or
      // stale data can be served after login.
      await _cacheManager.clearAll();
      debugPrint('[AccountSwitch] login(): all caches cleared');
      // Await the PULSE backend session before exposing the authenticated
      // state, so the Reports tab cannot open with a missing token.
      await _establishBackendSession(username, password);
      await _revokeStaffSession(previousStaff);
      await _sessionManager.clearStaffSession();
      state = AuthState(
        status: AuthStatus.authenticated,
        username: username,
        role: AuthRole.student,
      );
      unawaited(_syncAfterBackendLogin());
    } catch (e) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: _errorMessage(e),
      );
    }
  }

  /// Signs in with a locally provisioned staff/admin account.
  ///
  /// The backend verifies the credentials and supplies the role. This method
  /// never accepts a role from the UI or request body.
  Future<void> staffLogin(String username, String password) async {
    if (state.isLoading) return;

    final normalizedUsername = username.trim();
    if (normalizedUsername.isEmpty || password.isEmpty) {
      state = const AuthState(
        status: AuthStatus.unauthenticated,
        error: 'Enter your staff username and password.',
      );
      return;
    }

    state = state.copyWith(isLoading: true, error: null);
    StaffSession? issuedSession;
    try {
      final backend = _ref.read(pulseBackendServiceProvider);
      issuedSession = await backend.staffLogin(normalizedUsername, password);

      // A staff login must never leave a usable student identity or stale
      // student backend token on the device.
      await _clearPushRegistration();
      await _authRepository.logout();
      await _sessionManager.saveStaffSession(issuedSession);
      await _cacheManager.clearAll();
      await _clearNotificationState();

      state = AuthState(
        status: AuthStatus.authenticated,
        username: issuedSession.username,
        role: AuthRole.fromStaffRole(issuedSession.role),
        staffSession: issuedSession,
      );
    } catch (e) {
      if (issuedSession != null) {
        await _revokeStaffSession(issuedSession);
      }
      await _sessionManager.clearStaffSession();
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: _errorMessage(e),
      );
    }
  }

  Future<void> logout() async {
    final staff = state.staffSession;
    await _clearSessionState(staffSession: staff);
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> handleSessionExpired() async {
    // One expired session makes every in-flight request answer 401, so this
    // can be re-entered several times in a row (e.g. the three term-resolution
    // calls in a row). A single logout is enough.
    if (_handlingSessionExpiry) return;
    _handlingSessionExpiry = true;
    try {
      final staff = state.staffSession;
      await _clearSessionState(staffSession: staff);
      state = const AuthState(
        status: AuthStatus.unauthenticated,
        error: 'Your session expired. Please sign in again.',
      );
    } finally {
      _handlingSessionExpiry = false;
    }
  }

  /// Clears a transient login error without changing the authentication state.
  void clearError() {
    if (state.error != null) {
      state = state.copyWith(error: null);
    }
  }

  Future<void> _clearSessionState({StaffSession? staffSession}) async {
    await _clearPushRegistration();
    await _revokeStaffSession(staffSession);
    await _authRepository.logout();
    await _sessionManager.clearStaffSession();
    await _cacheManager.clearAll();
    await _clearNotificationState();
  }

  Future<void> _revokeStaffSession(StaffSession? session) async {
    if (session == null) return;
    try {
      await _ref
          .read(pulseBackendServiceProvider)
          .staffLogout(session.accessToken);
    } catch (e) {
      debugPrint('[PULSE backend] staff logout failed: $e');
    }
  }

  Future<void> _clearNotificationState() async {
    try {
      final store = _ref.read(notificationStateStoreProvider);
      await store.clearOperationalState();
      final service = _ref.read(notificationServiceProvider);
      await service?.cancelAll();
    } catch (e) {
      debugPrint('[Notifications] session cleanup failed: $e');
    }
  }

  String _errorMessage(Object error) {
    if (error is ApiException) return error.message;
    if (error is FormatException) {
      return 'The server returned an invalid staff session. Please try again.';
    }
    return error.toString();
  }
}
