import '../../providers/auth_provider.dart';

/// The authenticated home that corresponds to the backend-issued role.
enum AuthLanding { student, staff, admin }

/// Resolves the landing screen for the current auth state.
///
/// Only a backend-issued STAFF/ADMIN role enters the staff area. A legacy or
/// missing role is treated as a student session; an unauthenticated or still
/// restoring session has no landing.
AuthLanding? authLandingFor(AuthState auth) {
  if (auth.status != AuthStatus.authenticated) return null;
  return switch (auth.role) {
    AuthRole.admin => AuthLanding.admin,
    AuthRole.staff => AuthLanding.staff,
    AuthRole.student || null => AuthLanding.student,
  };
}
