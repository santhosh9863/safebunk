class ApiConstants {
  ApiConstants._();

  static const String baseUrl = 'https://sfcv4.linways.com';
  static const String apiPrefix = '/academics/api/v1';
  static String get apiBaseUrl => '';

  static const String login = '/auth/student-login-credentials';
  static const String dailyAttendance = '/attendance/daily-attendance';
  static const String subjectWiseAttendance = '/attendance/subject-wise-attendance-report';
  static const String studentBasicDetails = '/student/get-student-basic-details';

  static const String studentId = 'studentId';
  static const String fromDate = 'fromDate';
  static const String toDate = 'toDate';
  static const String emitAsResetWhileReset = 'emitAsResetWhileReset';

  static const String timetable = '/timetable';
  static const String studentDailySchedule = '/student/get-my-daily-schedule';
  static const String timetableDayHours = '/timetable/day-hours';
  static const String timetableDayOrders = '/timetable/day-orders';
  static const String getDaywise = 'getDaywise';
  static const String batchId = 'batchId';

  static const String username = 'username';
  static const String password = 'password';
  static const String next = 'next';
  static const String userType = 'userType';

  static const String authSessionCookie = 'AUTH_SESSION';
  static const String cookieHeader = 'Cookie';
  static const String authorizationHeader = 'Authorization';
  static const String setCookieHeader = 'set-cookie';
  static const String bearerPrefix = 'Bearer ';
}
