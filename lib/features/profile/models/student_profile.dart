class StudentProfile {
  final String name;
  final String registerNumber;
  final String department;
  final String academicTerm;
  final String studentId;

  const StudentProfile({
    required this.name,
    required this.registerNumber,
    required this.department,
    required this.academicTerm,
    required this.studentId,
  });

  factory StudentProfile.fromJson(Map<String, dynamic> json) {
    final properties = _safeMap(json['properties']);
    return StudentProfile(
      name: _safeString(json['name']),
      registerNumber: _safeString(properties['registerNumber']),
      department: _safeString(json['department']),
      academicTerm: _safeString(json['academicTermName']),
      studentId: _safeString(json['studentId'] ?? json['id']),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'registerNumber': registerNumber,
    'department': department,
    'academicTerm': academicTerm,
    'studentId': studentId,
  };

  static String _safeString(dynamic value) {
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return '';
  }

  static Map<String, dynamic> _safeMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return {};
  }
}
