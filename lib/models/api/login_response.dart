class LoginResponse {
  final bool success;
  final String? message;
  final LoginData? data;
  final String? cookies;

  const LoginResponse({
    required this.success,
    this.message,
    this.data,
    this.cookies,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String?,
      data: json['data'] is Map<String, dynamic>
          ? LoginData.fromJson(json['data'] as Map<String, dynamic>)
          : null,
    );
  }

  LoginResponse copyWith({String? cookies}) {
    return LoginResponse(
      success: success,
      message: message,
      data: data,
      cookies: cookies ?? this.cookies,
    );
  }
}

class LoginData {
  final int? id;
  final String? token;
  final String? admissionNo;
  final String? studentName;
  final String? registerNumber;
  final String? batch;
  final String? department;
  final String? email;

  const LoginData({
    this.id,
    this.token,
    this.admissionNo,
    this.studentName,
    this.registerNumber,
    this.batch,
    this.department,
    this.email,
  });

  static int? _parseId(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  factory LoginData.fromJson(Map<String, dynamic> json) {
    final id = _parseId(json['id']);
    return LoginData(
      id: id,
      token: json['token'] as String? ?? json['accessToken'] as String?,
      admissionNo: json['admission_no'] as String? ?? json['admissionNo'] as String?,
      studentName: json['student_name'] as String? ?? json['studentName'] as String? ?? json['name'] as String?,
      registerNumber: json['register_number'] as String? ?? json['registerNumber'] as String?,
      batch: json['batch'] as String?,
      department: json['department'] as String? ?? json['dept'] as String?,
      email: json['email'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    if (token != null) 'token': token,
    if (admissionNo != null) 'admission_no': admissionNo,
    if (studentName != null) 'student_name': studentName,
    if (registerNumber != null) 'register_number': registerNumber,
    if (batch != null) 'batch': batch,
    if (department != null) 'department': department,
    if (email != null) 'email': email,
  };
}
