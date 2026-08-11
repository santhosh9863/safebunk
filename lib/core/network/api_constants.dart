class ApiConstants {
  ApiConstants._();

  static const String baseUrl = 'https://sfcv4.linways.com';
  static const String apiPrefix = '/academics/api/v1';
  static String get apiBaseUrl => '$baseUrl$apiPrefix';

  static const String login = '/auth/student-login-credentials';
  static const String dailyAttendance = '/attendance/daily-attendance';
  static const String dailyAttendanceDateFetch = '/attendance/daily-attendance-date-fetch';
  static const String subjectWiseAttendance = '/attendance/subject-wise-attendance-report';
  static const String studiedTerms = '/attendance/fetch-student-studied-terms';
  static const String studentBasicDetails = '/student/get-student-basic-details';

  static const String studentId = 'studentId';
  static const String fromDate = 'fromDate';
  static const String toDate = 'toDate';
  static const String emitAsResetWhileReset = 'emitAsResetWhileReset';

  static const String username = 'username';
  static const String password = 'password';
  static const String next = 'next';
  static const String userType = 'userType';

  static const String storageCookies = 'session_cookies';
  static const String storageUsername = 'saved_username';
  static const String storageStudentId = 'saved_student_id';
  static const String storageStudentData = 'saved_student_data';

  static const String authSessionCookie = 'AUTH_SESSION';

  static const String cookieHeader = 'Cookie';
  static const String authorizationHeader = 'Authorization';
  static const String setCookieHeader = 'set-cookie';
  static const String bearerPrefix = 'Bearer ';
}
