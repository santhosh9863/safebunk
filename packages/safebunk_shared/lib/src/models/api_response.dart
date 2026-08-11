class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? message;
  final int? statusCode;

  const ApiResponse({
    required this.success,
    this.data,
    this.message,
    this.statusCode,
  });

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic)? fromJsonT,
  ) {
    return ApiResponse(
      success: json['success'] as bool? ?? false,
      data: json['data'] != null && fromJsonT != null
          ? fromJsonT(json['data'])
          : json['data'] as T?,
      message: json['message'] as String?,
      statusCode: json['statusCode'] as int?,
    );
  }

  Map<String, dynamic> toJson(Map<String, dynamic> Function(T)? toJsonT) {
    return {
      'success': success,
      if (data != null && toJsonT != null) 'data': toJsonT(data as T),
      if (data != null && toJsonT == null) 'data': data,
      if (message != null) 'message': message,
      if (statusCode != null) 'statusCode': statusCode,
    };
  }

  @override
  String toString() =>
      'ApiResponse(success: , data: , message: , statusCode: )';
}
