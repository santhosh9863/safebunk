import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/models/auth/staff_account.dart';
import 'package:safebunk_v2/models/auth/staff_session.dart';

void main() {
  group('StaffSession', () {
    test('parses a backend STAFF response without accepting a client role', () {
      final session = StaffSession.fromLoginJson({
        'accessToken': 'token-1',
        'staff': {
          'id': 'staff-1',
          'username': 'campus.staff',
          'displayName': 'Campus Staff',
          'role': 'STAFF',
        },
      });

      expect(session.accessToken, 'token-1');
      expect(session.staffId, 'staff-1');
      expect(session.username, 'campus.staff');
      expect(session.displayName, 'Campus Staff');
      expect(session.role, StaffRole.staff);
      expect(session.displayLabel, 'Campus Staff');
    });

    test('parses an ADMIN response', () {
      final session = StaffSession.fromLoginJson({
        'accessToken': 'token-2',
        'staff': {
          'id': 'staff-2',
          'username': 'campus.admin',
          'displayName': null,
          'role': 'ADMIN',
        },
      });

      expect(session.role, StaffRole.admin);
      expect(session.displayLabel, 'campus.admin');
    });

    test('rejects an unknown or missing role instead of defaulting', () {
      expect(
        () => StaffSession.fromLoginJson({
          'accessToken': 'token',
          'staff': {'id': 'id', 'username': 'user', 'role': 'SUPERADMIN'},
        }),
        throwsFormatException,
      );

      expect(
        () => StaffSession.fromLoginJson({
          'accessToken': 'token',
          'staff': {'id': 'id', 'username': 'user'},
        }),
        throwsFormatException,
      );
    });

    test('rejects a missing token or malformed staff payload', () {
      expect(
        () => StaffSession.fromLoginJson({
          'staff': {'id': 'id', 'username': 'user', 'role': 'STAFF'},
        }),
        throwsFormatException,
      );
      expect(
        () => StaffSession.fromLoginJson({
          'accessToken': 'token',
          'staff': 'not-a-map',
        }),
        throwsFormatException,
      );
    });

    test('round-trips through JSON and rejects an invalid stored role', () {
      const original = StaffSession(
        accessToken: 'token',
        staffId: 'staff-1',
        username: 'campus.staff',
        role: StaffRole.staff,
      );

      final restored = StaffSession.fromJson(original.toJson());
      expect(restored.accessToken, original.accessToken);
      expect(restored.role, original.role);

      expect(
        () => StaffSession.fromJson({
          'accessToken': 'token',
          'staffId': 'staff-1',
          'username': 'campus.staff',
          'role': 'UNKNOWN',
        }),
        throwsFormatException,
      );
    });
  });

  group('StaffAccount', () {
    test('parses active/admin accounts', () {
      final account = StaffAccount.fromJson({
        'id': 'staff-1',
        'username': 'campus.admin',
        'displayName': 'Campus Admin',
        'role': 'ADMIN',
        'active': true,
        'createdAt': '2026-10-20T10:00:00.000Z',
      });

      expect(account.role, StaffRole.admin);
      expect(account.active, isTrue);
      expect(account.displayLabel, 'Campus Admin');
      expect(account.createdAt, isNotNull);
    });

    test('rejects an unknown role and defaults non-true active to false', () {
      final account = StaffAccount.fromJson({
        'id': 'staff-1',
        'username': 'campus.staff',
        'role': 'STAFF',
        'active': 'true',
      });

      expect(account.active, isFalse);
      expect(
        () => StaffAccount.fromJson({
          'id': 'staff-1',
          'username': 'campus.staff',
          'role': 'ROOT',
          'active': true,
        }),
        throwsFormatException,
      );
    });
  });
}
