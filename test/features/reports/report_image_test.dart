import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/features/reports/domain/report_image.dart';

void main() {
  group('resolveReportImageContentType', () {
    test('maps known extensions to MIME types (case-insensitive)', () {
      expect(resolveReportImageContentType('photo.JPG'), 'image/jpeg');
      expect(resolveReportImageContentType('photo.jpeg'), 'image/jpeg');
      expect(resolveReportImageContentType('photo.png'), 'image/png');
      expect(resolveReportImageContentType('deep/path/photo.webp'), 'image/webp');
    });

    test('falls back to a declared supported MIME type', () {
      expect(resolveReportImageContentType('blob', 'image/png'), 'image/png');
    });

    test('returns null for unsupported or unknown types', () {
      expect(resolveReportImageContentType('notes.txt'), isNull);
      expect(resolveReportImageContentType('archive.zip', 'application/zip'), isNull);
      expect(resolveReportImageContentType('noextension'), isNull);
    });
  });

  group('validateReportImage', () {
    test('accepts a supported image within the size limit', () {
      expect(
        validateReportImage(fileName: 'photo.jpg', sizeBytes: 1024),
        isNull,
      );
    });

    test('rejects empty, oversize and unsupported files', () {
      expect(validateReportImage(fileName: 'photo.jpg', sizeBytes: 0), isNotNull);
      expect(
        validateReportImage(
          fileName: 'photo.jpg',
          sizeBytes: maxReportImageBytes + 1,
        ),
        isNotNull,
      );
      expect(
        validateReportImage(fileName: 'photo.gif', sizeBytes: 1024),
        isNotNull,
      );
    });
  });
}
