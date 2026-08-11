import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/features/notifications/domain/enums/notification_type.dart';
import 'package:safebunk_v2/features/notifications/domain/services/notification_rule_engine.dart';

void main() {
  const engine = NotificationRuleEngine();

  group('evaluateAttendance (spec scenarios)', () {
    test('75 -> 68 emits attendanceDropped', () {
      final events = engine.evaluateAttendance(
        currentPercentage: 68,
        previousPercentage: 75,
        target: 75,
        dangerThreshold: 60,
      );

      expect(events, hasLength(1));
      expect(events.single.type, NotificationType.attendanceDropped);
    });

    test('74 -> 76 emits enteredSafeZone', () {
      final events = engine.evaluateAttendance(
        currentPercentage: 76,
        previousPercentage: 74,
        target: 75,
        dangerThreshold: 60,
      );

      expect(events, hasLength(1));
      expect(events.single.type, NotificationType.enteredSafeZone);
    });

    test('60 -> 59 emits enteredDangerZone', () {
      final events = engine.evaluateAttendance(
        currentPercentage: 59,
        previousPercentage: 60,
        target: 75,
        dangerThreshold: 60,
      );

      expect(events, hasLength(1));
      expect(events.single.type, NotificationType.enteredDangerZone);
    });

    test('68 -> 68 emits nothing', () {
      final events = engine.evaluateAttendance(
        currentPercentage: 68,
        previousPercentage: 68,
        target: 75,
        dangerThreshold: 60,
      );

      expect(events, isEmpty);
    });

    test('no previous baseline emits nothing', () {
      final events = engine.evaluateAttendance(
        currentPercentage: 68,
        previousPercentage: null,
      );

      expect(events, isEmpty);
    });

    test('already in danger, dropping further reports direction', () {
      final events = engine.evaluateAttendance(
        currentPercentage: 58,
        previousPercentage: 59,
      );

      expect(events.single.type, NotificationType.attendanceDropped);
    });

    test('safe zone takes precedence over improvement (74 -> 76)', () {
      final events = engine.evaluateAttendance(
        currentPercentage: 76,
        previousPercentage: 74,
      );

      expect(events.single.type, NotificationType.enteredSafeZone);
    });

    test('recoveredFromDanger fires when leaving danger but not yet safe', () {
      final events = engine.evaluateAttendance(
        currentPercentage: 62,
        previousPercentage: 59,
      );

      expect(events.single.type, NotificationType.recoveredFromDanger);
    });

    test('perfectAttendance fires when reaching 100', () {
      final events = engine.evaluateAttendance(
        currentPercentage: 100,
        previousPercentage: 99,
      );

      expect(events.single.type, NotificationType.perfectAttendance);
    });

    test('staying inside danger reports direction, not re-entry', () {
      final events = engine.evaluateAttendance(
        currentPercentage: 58,
        previousPercentage: 59,
        target: 75,
        dangerThreshold: 60,
      );

      expect(events.single.type, NotificationType.attendanceDropped);
    });
  });

  group('evaluateMilestones', () {
    test('crossing 80 emits reached80', () {
      final events = engine.evaluateMilestones(
        currentPercentage: 81,
        previousPercentage: 79,
      );

      expect(events.single.type, NotificationType.reached80);
    });

    test('crossing 90 and 95 at once emits both', () {
      final events = engine.evaluateMilestones(
        currentPercentage: 96,
        previousPercentage: 89,
      );

      expect(events.map((e) => e.type),
          containsAll([NotificationType.reached90, NotificationType.reached95]));
    });

    test('no milestone on a decline', () {
      final events = engine.evaluateMilestones(
        currentPercentage: 79,
        previousPercentage: 81,
      );

      expect(events, isEmpty);
    });
  });

  group('evaluateBunks (spec scenarios)', () {
    test('safe bunk gained 0 -> 1 emits safeToBunk', () {
      final events = engine.evaluateBunks(
        safeBunks: 1,
        previousSafeBunks: 0,
        present: 60,
        total: 80,
      );

      expect(events.map((e) => e.type), contains(NotificationType.safeToBunk));
    });

    test('safe bunks exhausted 1 -> 0 emits noSafeBunks', () {
      final events = engine.evaluateBunks(
        safeBunks: 0,
        previousSafeBunks: 1,
        present: 60,
        total: 80,
      );

      expect(events.map((e) => e.type), contains(NotificationType.noSafeBunks));
    });

    test('dropping to the last bunk emits lastSafeBunk', () {
      final events = engine.evaluateBunks(
        safeBunks: 1,
        previousSafeBunks: 3,
        present: 60,
        total: 80,
      );

      expect(events.map((e) => e.type), contains(NotificationType.lastSafeBunk));
    });

    test('no bunk event when nothing changed', () {
      final events = engine.evaluateBunks(
        safeBunks: 2,
        previousSafeBunks: 2,
        present: 70,
        total: 100,
        target: 75,
        dangerThreshold: 60,
      );

      expect(events, isEmpty);
    });

    test('bunkWouldCauseDanger when skipping drops below danger zone', () {
      // 54/80 = 67.5%, after bunk 66.7% — still above 60, no event.
      final noEvent = engine.evaluateBunks(
        safeBunks: 5,
        previousSafeBunks: 5,
        present: 54,
        total: 80,
        target: 75,
        dangerThreshold: 60,
      );
      expect(noEvent, isEmpty);

      // 38/50 = 76% — above target. After bunk: 38/51 = 74.5% < 75.
      final crossSafe = engine.evaluateBunks(
        safeBunks: 2,
        previousSafeBunks: 2,
        present: 38,
        total: 50,
        target: 75,
        dangerThreshold: 60,
      );
      expect(crossSafe.map((e) => e.type),
          contains(NotificationType.bunkWouldCrossSafeThreshold));

      // 48/80 = 60% — exactly at the danger line. After bunk: 48/81 = 59.3% < 60.
      final causeDanger = engine.evaluateBunks(
        safeBunks: 1,
        previousSafeBunks: 1,
        present: 48,
        total: 80,
        target: 75,
        dangerThreshold: 60,
      );
      expect(causeDanger.map((e) => e.type),
          contains(NotificationType.bunkWouldCauseDanger));
    });
  });
}
