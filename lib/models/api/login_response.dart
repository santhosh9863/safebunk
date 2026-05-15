class LoginResponse {
  final bool success;
  final String? message;
  final Map<String, dynamic>? data;
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
      data: json['data'] as Map<String, dynamic>?,
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
