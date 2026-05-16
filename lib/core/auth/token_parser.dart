import 'dart:convert';

class TokenParser {
  TokenParser._();

  static String? extractAccessToken(String? cookies) {
    if (cookies == null || cookies.isEmpty) return null;
    final pattern = RegExp('AUTH_SESSION=([^;]+)');
    final match = pattern.firstMatch(cookies);
    return match?.group(1);
  }

  static String? decodeUserId(String token) {
    if (token.isEmpty) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final payloadJson = jsonDecode(decoded) as Map<String, dynamic>;
      final data = payloadJson['data'] as Map<String, dynamic>?;
      return data?['userId'] as String?;
    } catch (_) {
      return null;
    }
  }

  static String? extractStudentId({
    int? explicitId,
    String? rawToken,
    String? cookies,
  }) {
    if (explicitId != null) return explicitId.toString();
    if (rawToken != null) {
      final userId = decodeUserId(rawToken);
      if (userId != null) return userId;
    }
    final accessToken = extractAccessToken(cookies);
    if (accessToken != null) {
      final userId = decodeUserId(accessToken);
      if (userId != null) return userId;
    }
    return null;
  }
}
