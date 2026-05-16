class SessionData {
  final String? accessToken;
  final String? refreshToken;
  final String? studentId;
  final String? username;
  final String? cookies;
  final Map<String, dynamic>? studentData;

  const SessionData({
    this.accessToken,
    this.refreshToken,
    this.studentId,
    this.username,
    this.cookies,
    this.studentData,
  });

  SessionData copyWith({
    String? accessToken,
    String? refreshToken,
    String? studentId,
    String? username,
    String? cookies,
    Map<String, dynamic>? studentData,
  }) {
    return SessionData(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      studentId: studentId ?? this.studentId,
      username: username ?? this.username,
      cookies: cookies ?? this.cookies,
      studentData: studentData ?? this.studentData,
    );
  }
}
