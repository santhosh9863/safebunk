import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/core/auth/auth_landing.dart';
import 'package:safebunk_v2/features/staff/presentation/staff_navigation.dart';
import 'package:safebunk_v2/models/auth/staff_session.dart';
import 'package:safebunk_v2/providers/auth_provider.dart';

void main() {
  group('authLandingFor', () {
    test('only backend-issued staff roles enter the staff area', () {
      expect(
        authLandingFor(
          const AuthState(
            status: AuthStatus.authenticated,
            role: AuthRole.staff,
          ),
        ),
        AuthLanding.staff,
      );
      expect(
        authLandingFor(
          const AuthState(
            status: AuthStatus.authenticated,
            role: AuthRole.admin,
          ),
        ),
        AuthLanding.admin,
      );
    });

    test('students and legacy null-role sessions stay in the student area', () {
      expect(
        authLandingFor(
          const AuthState(
            status: AuthStatus.authenticated,
            role: AuthRole.student,
          ),
        ),
        AuthLanding.student,
      );
      expect(
        authLandingFor(const AuthState(status: AuthStatus.authenticated)),
        AuthLanding.student,
      );
    });

    test('unauthenticated and restoring sessions have no landing', () {
      expect(
        authLandingFor(const AuthState(status: AuthStatus.unauthenticated)),
        isNull,
      );
      expect(authLandingFor(AuthState.unknown), isNull);
    });

    test('maps staff role values without trusting arbitrary strings', () {
      expect(AuthRole.fromStaffRole(StaffRole.staff), AuthRole.staff);
      expect(AuthRole.fromStaffRole(StaffRole.admin), AuthRole.admin);
    });
  });

  group('staffSectionsFor', () {
    test('STAFF never receives the staff-account section', () {
      expect(staffSectionsFor(StaffRole.staff), [
        StaffSection.reports,
        StaffSection.account,
      ]);
    });

    test('ADMIN receives the additional staff-account section', () {
      expect(staffSectionsFor(StaffRole.admin), [
        StaffSection.reports,
        StaffSection.staffAccounts,
        StaffSection.account,
      ]);
    });
  });
}
