import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/core/errors/app_exceptions.dart';
import 'package:safebunk_v2/services/api/pulse_backend_service.dart';

void main() {
  group('PulseBackendService configuration', () {
    test(
      'placeholder URL is disabled and Reports throws an actionable error',
      () async {
        final service = PulseBackendService(baseUrl: 'https://<host:port>');

        expect(service.isEnabled, isFalse);
        expect(
          service.configurationError,
          contains('not a valid backend origin'),
        );

        await expectLater(
          service.fetchMyReports(),
          throwsA(
            isA<NetworkException>().having(
              (e) => e.message,
              'message',
              contains('PULSE_BACKEND_URL'),
            ),
          ),
        );
      },
    );

    test('missing URL produces the same actionable failure', () async {
      final service = PulseBackendService(baseUrl: '');

      expect(service.isEnabled, isFalse);
      await expectLater(
        service.fetchMyReports(),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'message',
            contains('not configured'),
          ),
        ),
      );
    });

    test('absoluteUrl uses the normalized origin for attachment paths', () {
      final service = PulseBackendService(baseUrl: 'http://localhost:3000/');

      expect(
        service.absoluteUrl('/api/reports/attachments/abc'),
        'http://localhost:3000/api/reports/attachments/abc',
      );
    });

    test('absoluteUrl stays null when configuration is invalid', () {
      final service = PulseBackendService(baseUrl: 'https://<host:port>');
      expect(service.absoluteUrl('/api/reports/attachments/abc'), isNull);
    });
  });
}
