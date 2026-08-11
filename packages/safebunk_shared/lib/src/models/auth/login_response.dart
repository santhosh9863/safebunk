class StudentInfo {
  final String studentId;
  final String name;
  final String batch;
  final String username;

  const StudentInfo({
    required this.studentId,
    required this.name,
    required this.batch,
    required this.username,
  });

  factory StudentInfo.fromJson(Map<String, dynamic> json) => StudentInfo(
    studentId: json['studentId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    batch: json['batch'] as String? ?? '',
    username: json['username'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'studentId': studentId,
    'name': name,
    'batch': batch,
    'username': username,
  };
}

class LoginResponse {
  final String accessToken;
  final StudentInfo student;

  const LoginResponse({required this.accessToken, required this.student});

  factory LoginResponse.fromJson(Map<String, dynamic> json) => LoginResponse(
    accessToken: json['accessToken'] as String? ?? '',
    student: StudentInfo.fromJson(json['student'] as Map<String, dynamic>? ?? {}),
  );

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'student': student.toJson(),
  };
}
