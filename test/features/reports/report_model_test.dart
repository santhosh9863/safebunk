import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/features/reports/data/models/report_event.dart';
import 'package:safebunk_v2/features/reports/data/models/report_model.dart';
import 'package:safebunk_v2/features/reports/domain/report_enums.dart';
import 'package:safebunk_v2/features/reports/presentation/report_format.dart';
import 'package:safebunk_v2/models/auth/staff_session.dart';

void main() {
  group('ReportModel.fromJson', () {
    test('parses a backend report summary', () {
      final report = ReportModel.fromJson({
        'id': 'rep_1',
        'code': 'PULSE-1042',
        'title': 'Water Leakage',
        'description': 'Water leaking near the electrical panel.',
        'category': 'Plumbing',
        'location': 'Block B · 2nd Floor',
        'priority': 'HIGH',
        'status': 'IN_PROGRESS',
        'assignedDepartment': null,
        'aiCategory': null,
        'aiPriority': null,
        'aiConfidence': null,
        'createdAt': '2026-10-06T10:00:00.000Z',
        'updatedAt': '2026-10-06T11:00:00.000Z',
        'resolvedAt': null,
      });

      expect(report.id, 'rep_1');
      expect(report.code, 'PULSE-1042');
      expect(report.description, 'Water leaking near the electrical panel.');
      expect(report.statusEnum, ReportStatus.inProgress);
      expect(report.priorityEnum, ReportPriority.high);
      expect(report.assignedDepartment, isNull);
      expect(report.resolvedAt, isNull);
    });

    test('defaults missing/unknown values safely', () {
      final report = ReportModel.fromJson({'id': 'x'});
      expect(report.statusEnum, ReportStatus.submitted);
      expect(report.priorityEnum, ReportPriority.medium);
      expect(report.description, '');
      expect(report.events, isEmpty);
      expect(report.assignedStaff, isNull);
    });

    test('parses assignment, resolution notes, and status history', () {
      final report = ReportModel.fromJson({
        'id': 'rep_2',
        'code': 'PULSE-1043',
        'title': 'Broken light',
        'description': 'Corridor light is out.',
        'priority': 'MEDIUM',
        'status': 'RESOLVED',
        'assignedDepartment': 'Maintenance',
        'assignedAt': '2026-10-20T10:00:00.000Z',
        'resolutionNotes': 'Replaced the tube light.',
        'assignedStaff': {
          'id': 'staff_a',
          'username': 'staff.a',
          'displayName': 'Staff A',
          'role': 'STAFF',
          'active': true,
        },
        'events': [
          {
            'id': 'evt_1',
            'type': 'SUBMITTED',
            'actorRole': 'STUDENT',
            'remark': null,
            'createdAt': '2026-10-20T09:00:00.000Z',
          },
          {
            'id': 'evt_2',
            'type': 'PROGRESS_NOTE',
            'actorRole': 'STAFF',
            'remark': 'Tube ordered.',
            'createdAt': '2026-10-20T10:15:00.000Z',
          },
          {
            'id': 'evt_3',
            'type': 'RESOLVED',
            'actorRole': 'STAFF',
            'remark': 'Replaced the tube light.',
            'createdAt': '2026-10-20T11:00:00.000Z',
          },
        ],
        'createdAt': '2026-10-20T09:00:00.000Z',
        'updatedAt': '2026-10-20T11:00:00.000Z',
      });

      expect(report.assignedStaff?.displayLabel, 'Staff A');
      expect(report.assignedStaff?.role, StaffRole.staff);
      expect(report.assignedAt, isNotNull);
      expect(report.assignedDepartment, 'Maintenance');
      expect(report.resolutionNotes, 'Replaced the tube light.');
      expect(report.events, hasLength(3));
      expect(report.events[1].typeEnum, ReportEventType.progressNote);
      expect(report.events[1].remark, 'Tube ordered.');
      expect(report.events.last.typeEnum, ReportEventType.resolved);
    });
  });

  group('ReportStatus', () {
    test('maps backend values and falls back to submitted', () {
      expect(ReportStatus.fromApi('ASSIGNED'), ReportStatus.assigned);
      expect(ReportStatus.fromApi('in_progress'), ReportStatus.inProgress);
      expect(ReportStatus.fromApi(null), ReportStatus.submitted);
      expect(ReportStatus.fromApi('NONSENSE'), ReportStatus.submitted);
    });

    test('terminal vs open classification', () {
      expect(ReportStatus.resolved.isTerminal, isTrue);
      expect(ReportStatus.rejected.isTerminal, isTrue);
      expect(ReportStatus.submitted.isOpen, isTrue);
      expect(ReportStatus.inProgress.isOpen, isTrue);
    });
  });

  group('formatRelativeTime', () {
    final now = DateTime(2026, 10, 9, 12, 0);

    test('humanizes recent timestamps', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(seconds: 10)), now: now),
        'Just now',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 5)), now: now),
        '5m ago',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 3)), now: now),
        '3h ago',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 2)), now: now),
        '2d ago',
      );
    });

    test('falls back to an absolute date for older items', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 30)), now: now),
        '09 Sep 2026',
      );
    });
  });
}
