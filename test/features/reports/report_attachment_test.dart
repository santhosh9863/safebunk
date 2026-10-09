import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/features/reports/data/models/report_attachment.dart';

void main() {
  group('ReportAttachment.fromJson', () {
    test('parses a backend attachment response', () {
      final attachment = ReportAttachment.fromJson({
        'id': 'att_1',
        'url': '/api/reports/attachments/att_1',
        'contentType': 'image/png',
        'size': 2048,
        'createdAt': '2026-10-09T10:00:00.000Z',
      });

      expect(attachment.id, 'att_1');
      expect(attachment.url, '/api/reports/attachments/att_1');
      expect(attachment.contentType, 'image/png');
      expect(attachment.size, 2048);
      expect(attachment.createdAt, isNotNull);
    });

    test('defaults missing fields without throwing', () {
      final attachment = ReportAttachment.fromJson({'id': 'att_2'});
      expect(attachment.id, 'att_2');
      expect(attachment.url, '');
      expect(attachment.contentType, 'application/octet-stream');
      expect(attachment.size, 0);
      expect(attachment.createdAt, isNull);
    });

    test('coerces numeric strings for size', () {
      final attachment = ReportAttachment.fromJson({'id': 'x', 'size': '1024'});
      expect(attachment.size, 1024);
    });
  });
}
