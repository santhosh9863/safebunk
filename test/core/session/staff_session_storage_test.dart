import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/core/network/api_constants.dart';
import 'package:safebunk_v2/core/session/session_manager.dart';
import 'package:safebunk_v2/core/storage/secure_storage_service.dart';
import 'package:safebunk_v2/models/auth/staff_session.dart';
import 'package:safebunk_v2/models/auth/session_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'staff session persists securely and replaces a student session',
    () async {
      final storage = SecureStorageService();
      final manager = SessionManager(storage);

      await manager.saveSession(
        const SessionData(
          cookies: 'AUTH_SESSION=student',
          username: 'student',
          studentId: 'student-1',
        ),
      );

      const staff = StaffSession(
        accessToken: 'staff-token',
        staffId: 'staff-1',
        username: 'campus.staff',
        displayName: 'Campus Staff',
        role: StaffRole.staff,
      );

      await manager.saveStaffSession(staff);

      expect(await manager.restoreSession(), isNull);
      expect(await manager.hasStaffSession(), isTrue);

      final restored = await manager.restoreStaffSession();
      expect(restored, isNotNull);
      expect(restored!.accessToken, staff.accessToken);
      expect(restored.staffId, staff.staffId);
      expect(restored.username, staff.username);
      expect(restored.role, StaffRole.staff);
    },
  );

  test('student session replaces a staff session', () async {
    final storage = SecureStorageService();
    final manager = SessionManager(storage);

    await manager.saveStaffSession(
      const StaffSession(
        accessToken: 'staff-token',
        staffId: 'staff-1',
        username: 'campus.admin',
        role: StaffRole.admin,
      ),
    );

    await manager.saveSession(
      const SessionData(
        cookies: 'AUTH_SESSION=student',
        username: 'student',
        studentId: 'student-1',
      ),
    );

    expect(await manager.restoreStaffSession(), isNull);
    expect(await manager.hasStaffSession(), isFalse);

    final student = await manager.restoreSession();
    expect(student, isNotNull);
    expect(student!.username, 'student');
  });

  test('clearStaffSession removes the persisted session', () async {
    final manager = SessionManager(SecureStorageService());

    await manager.saveStaffSession(
      const StaffSession(
        accessToken: 'staff-token',
        staffId: 'staff-1',
        username: 'campus.admin',
        role: StaffRole.admin,
      ),
    );

    await manager.clearStaffSession();

    expect(await manager.restoreStaffSession(), isNull);
    expect(await manager.hasStaffSession(), isFalse);
  });

  test('malformed or unknown-role stored sessions are discarded', () async {
    final storage = SecureStorageService();
    final manager = SessionManager(storage);

    await storage.saveStaffSession(
      jsonEncode({
        'accessToken': 'staff-token',
        'staffId': 'staff-1',
        'username': 'campus.admin',
        'role': 'SUPERADMIN',
      }),
    );

    expect(await manager.restoreStaffSession(), isNull);
    expect(await storage.getStaffSession(), isNull);

    FlutterSecureStorage.setMockInitialValues({
      ApiConstants.storageStaffSession: '{not-json',
    });
    final malformedManager = SessionManager(SecureStorageService());
    expect(await malformedManager.restoreStaffSession(), isNull);
  });
}
