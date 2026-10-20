import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/services/api/pulse_backend_config.dart';

void main() {
  group('PulseBackendConfig.parse', () {
    test('missing value is disabled with actionable guidance', () {
      final config = PulseBackendConfig.parse('');
      expect(config.isEnabled, isFalse);
      expect(config.baseUrl, isNull);
      expect(config.error, PulseBackendConfig.missingMessage);
      expect(config.error, contains('http://localhost:3000'));
      expect(config.error, contains('http://10.0.2.2:3000'));
    });

    test('whitespace-only value is treated as missing', () {
      final config = PulseBackendConfig.parse('   ');
      expect(config.isEnabled, isFalse);
      expect(config.error, PulseBackendConfig.missingMessage);
    });

    test('literal placeholder is rejected instead of being called', () {
      final config = PulseBackendConfig.parse('https://<host:port>');
      expect(config.isEnabled, isFalse);
      expect(config.baseUrl, isNull);
      expect(config.error, contains('not a valid backend origin'));
    });

    test('local web/Windows origin is accepted', () {
      final config = PulseBackendConfig.parse('http://localhost:3000');
      expect(config.isEnabled, isTrue);
      expect(config.error, isNull);
      expect(config.baseUrl, 'http://localhost:3000');
    });

    test('Android emulator origin is accepted', () {
      final config = PulseBackendConfig.parse('http://10.0.2.2:3000');
      expect(config.isEnabled, isTrue);
      expect(config.baseUrl, 'http://10.0.2.2:3000');
    });

    test('trailing slash is normalized away', () {
      final config = PulseBackendConfig.parse('http://localhost:3000/');
      expect(config.baseUrl, 'http://localhost:3000');
    });

    test('path is rejected because the client adds /api itself', () {
      final config = PulseBackendConfig.parse('http://localhost:3000/api');
      expect(config.isEnabled, isFalse);
      expect(config.error, contains('Do not include /api'));
    });

    test('non-http scheme is rejected', () {
      final config = PulseBackendConfig.parse('ftp://localhost:3000');
      expect(config.isEnabled, isFalse);
      expect(config.error, contains('not a valid backend origin'));
    });

    test('credentials, query and fragment are rejected', () {
      for (final value in [
        'http://user:pass@localhost:3000',
        'http://localhost:3000?x=1',
        'http://localhost:3000#frag',
        'not-a-url',
      ]) {
        final config = PulseBackendConfig.parse(value);
        expect(config.isEnabled, isFalse, reason: value);
        expect(config.error, isNotNull, reason: value);
      }
    });
  });
}
