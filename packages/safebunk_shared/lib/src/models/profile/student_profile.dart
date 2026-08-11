class StudentProfile {
  final String studentId;
  final String name;
  final String batch;
  final String batchId;
  final String course;
  final String semester;
  final String rollNo;
  final String email;
  final String phone;
  final String? profileImage;

  const StudentProfile({
    required this.studentId,
    required this.name,
    required this.batch,
    required this.batchId,
    required this.course,
    required this.semester,
    required this.rollNo,
    required this.email,
    required this.phone,
    this.profileImage,
  });

  factory StudentProfile.fromJson(Map<String, dynamic> json) => StudentProfile(
    studentId: json['studentId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    batch: json['batch'] as String? ?? '',
    batchId: json['batchId'] as String? ?? '',
    course: json['course'] as String? ?? '',
    semester: json['semester'] as String? ?? '',
    rollNo: json['rollNo'] as String? ?? '',
    email: json['email'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    profileImage: json['profileImage'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'studentId': studentId,
    'name': name,
    'batch': batch,
    'batchId': batchId,
    'course': course,
    'semester': semester,
    'rollNo': rollNo,
    'email': email,
    'phone': phone,
    if (profileImage != null) 'profileImage': profileImage,
  };
}
