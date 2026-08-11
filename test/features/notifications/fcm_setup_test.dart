import 'package:flutter_test/flutter_test.dart';

import 'package:safebunk_v2/features/notifications/application/fcm_setup.dart';

void main() {
  group('channelIdForFcmType', () {
    test('routes urgent events to the alert channel', () {
      expect(channelIdForFcmType('enteredDangerZone'), 'attendance_alerts');
      expect(channelIdForFcmType('classMissed'), 'attendance_alerts');
    });

    test('routes everything else to reminders', () {
      expect(channelIdForFcmType('attendanceMarkedPresent'), 'reminders');
      expect(channelIdForFcmType('classStarting'), 'reminders');
      expect(channelIdForFcmType('timetableUpdated'), 'reminders');
      expect(channelIdForFcmType(null), 'reminders');
    });
  });
}
