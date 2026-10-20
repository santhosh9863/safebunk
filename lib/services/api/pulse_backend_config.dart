/// Validates the compile-time PULSE backend URL.
///
/// The value never comes from user input; it is injected with
/// `--dart-define=PULSE_BACKEND_URL=<origin>`. A missing or placeholder value
/// must disable backend features and produce an actionable message instead of
/// letting Dio fail with an opaque connection error.
library;

class PulseBackendConfig {
  static const defineName = 'PULSE_BACKEND_URL';

  /// Examples use local development addresses only. Production values must be
  /// supplied deliberately by the build; they are never guessed here.
  static const missingMessage =
      'PULSE backend is not configured. Run the app with '
      '--dart-define=PULSE_BACKEND_URL=http://localhost:3000 for web or '
      'Windows, http://10.0.2.2:3000 for the Android emulator, or '
      'http://YOUR_PC_LAN_IP:3000 for a physical Android device.';

  static const invalidMessage =
      'PULSE_BACKEND_URL is not a valid backend origin. Use '
      'http://localhost:3000 for web or Windows, http://10.0.2.2:3000 for the '
      'Android emulator, or http://YOUR_PC_LAN_IP:3000 for a physical device. '
      'Do not include /api, a path, credentials, a query or a fragment.';

  /// Normalized origin (no trailing slash), or null when unusable.
  final String? baseUrl;

  /// Actionable reason when [baseUrl] is null.
  final String? error;

  const PulseBackendConfig._({this.baseUrl, this.error});

  bool get isEnabled => baseUrl != null;

  factory PulseBackendConfig.parse(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return const PulseBackendConfig._(error: missingMessage);
    }
    if (value.contains('<') ||
        value.contains('>') ||
        value.contains(' ') ||
        value.contains('\n')) {
      return const PulseBackendConfig._(error: invalidMessage);
    }

    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return const PulseBackendConfig._(error: invalidMessage);
    }
    // The client appends `/api/...`; a path here would silently produce
    // duplicated or wrong routes. Credentials/query/fragment have no meaning.
    if (uri.path.isNotEmpty && uri.path != '/') {
      return const PulseBackendConfig._(error: invalidMessage);
    }
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      return const PulseBackendConfig._(error: invalidMessage);
    }

    final normalized = uri
        .replace(path: '', query: null, fragment: null)
        .toString();
    return PulseBackendConfig._(
      baseUrl: normalized.endsWith('/')
          ? normalized.substring(0, normalized.length - 1)
          : normalized,
    );
  }
}
