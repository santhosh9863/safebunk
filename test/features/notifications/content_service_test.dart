import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/features/notifications/domain/entities/notification_event.dart';
import 'package:safebunk_v2/features/notifications/domain/enums/notification_type.dart';
import 'package:safebunk_v2/features/notifications/domain/services/notification_content_service.dart';

void main() {
  const service = NotificationContentService();

  NotificationEvent eventOf(NotificationType type, {double? pct, String? subject}) {
    return NotificationEvent(
      type: type,
      attendancePercentage: pct,
      subjectName: subject,
    );
  }

  group('roasting toggle', () {
    test('roast and neutral wording differ', () {
      final event = eventOf(NotificationType.enteredDangerZone, pct: 58);
      final roast = service.build(event, roasting: true);
      final neutral = service.build(event, roasting: false);

      expect(roast.title, isNot(neutral.title));
      expect(roast.title, contains('cooked'));
      expect(neutral.title, isNot(contains('cooked')));
    });

    test('neutral wording is informational, no roast markers', () {
      final event = eventOf(NotificationType.attendanceDropped, pct: 68);
      final message = service.build(event, roasting: false);

      expect(message.body, contains('68.0'));
      expect(message.body, isNot(contains('cooked')));
      expect(message.body, isNot(contains('😭')));
    });

    test('roast body still carries the verified data', () {
      final event = eventOf(NotificationType.attendanceDropped, pct: 68.4);
      final message = service.build(event, roasting: true);

      expect(message.body, contains('68.4'));
    });
  });

  group('placeholder filling', () {
    test('percentage is filled into the body', () {
      final event = eventOf(NotificationType.attendanceDropped, pct: 68.5);
      final message = service.build(event, roasting: false);

      expect(message.body, contains('68.5'));
      expect(message.body, isNot(contains('{percentage}')));
    });

    test('no raw placeholders leak into the message', () {
      final event = eventOf(NotificationType.attendanceDropped, pct: 68);
      final message = service.build(event, roasting: false);

      expect(message.title + message.body, isNot(contains('{')));
    });

    test('missing faculty -> subject only, no faculty placeholder', () {
      final event = NotificationEvent(
        type: NotificationType.enteredWarningZone,
        attendancePercentage: 70,
        subjectName: 'Mathematics',
      );
      final message = service.build(event, roasting: true);

      expect(message.body, contains('Mathematics'));
      expect(message.body, isNot(contains('facultyName')));
    });

    test('provided facultyName metadata never leaks raw placeholder', () {
      final event = NotificationEvent(
        type: NotificationType.enteredWarningZone,
        attendancePercentage: 70,
        subjectName: 'Mathematics',
        metadata: {'facultyName': 'Dr. Rao'},
      );
      final message = service.build(event, roasting: true);

      expect(message.title + message.body, isNot(contains('facultyName')));
      expect(message.body, contains('Mathematics'));
    });
  });

  group('subject name cleaning', () {
    test('suffix in parentheses is stripped', () {
      final event = eventOf(NotificationType.classReminder10Min, subject: 'Maths (Eng)');
      final message = service.build(event, roasting: false);

      expect(message.body, contains('Maths'));
      expect(message.body, isNot(contains('(')));
    });

    test('metadata values interpolate (classCount, minutes, time, duration)', () {
      final heavy = service.build(
        NotificationEvent(
          type: NotificationType.heavyClassDay,
          metadata: {'classCount': 6},
        ),
        roasting: false,
      );
      expect(heavy.body, contains('6'));

      final next = service.build(
        NotificationEvent(
          type: NotificationType.nextClass,
          subjectName: 'Physics',
          metadata: {'minutes': 45},
        ),
        roasting: false,
      );
      expect(next.body, contains('45'));
    });
  });
}
