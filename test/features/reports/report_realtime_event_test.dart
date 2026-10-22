import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/features/reports/data/models/report_realtime_event.dart';

void main() {
  test('parses a valid report change payload', () {
    final event = ReportRealtimeEvent.tryParse({
      'eventId': 'evt_1',
      'reportId': 'report_1',
      'code': 'PULSE-1042',
      'status': 'RESOLVED',
      'change': 'resolved',
      'occurredAt': '2026-10-22T10:00:00.000Z',
    });

    expect(event, isNotNull);
    expect(event!.eventId, 'evt_1');
    expect(event.reportId, 'report_1');
    expect(event.code, 'PULSE-1042');
    expect(event.status, 'RESOLVED');
    expect(event.change, 'resolved');
    expect(event.occurredAt, DateTime.utc(2026, 10, 22, 10));
  });

  test('rejects partial or malformed payloads', () {
    expect(ReportRealtimeEvent.tryParse(null), isNull);
    expect(ReportRealtimeEvent.tryParse('not-a-map'), isNull);
    expect(
      ReportRealtimeEvent.tryParse({
        'eventId': 'evt_1',
        'reportId': 'report_1',
        'code': 'PULSE-1042',
      }),
      isNull,
    );
  });

  test('does not expose or require private report fields', () {
    final event = ReportRealtimeEvent.tryParse({
      'eventId': 'evt_1',
      'reportId': 'report_1',
      'code': 'PULSE-1042',
      'status': 'SUBMITTED',
      'change': 'created',
      'title': 'Private title',
      'description': 'Private description',
    });

    expect(event, isNotNull);
    expect(event!.code, 'PULSE-1042');
    expect(event.toString(), isNot(contains('Private title')));
    expect(event.toString(), isNot(contains('Private description')));
  });
}
