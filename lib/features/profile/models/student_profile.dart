class StudentProfile {
  final String name;
  final String rollNo;
  final String registerNo;
  final String programme;
  final String batchName;
  final String currentSem;
  final String imageUrl;

  final String registerNumber;
  final String department;
  final String academicTerm;
  final String studentId;

  const StudentProfile({
    required this.name,
    required this.rollNo,
    required this.registerNo,
    required this.programme,
    required this.batchName,
    required this.currentSem,
    required this.imageUrl,
    this.registerNumber = '',
    this.department = '',
    this.academicTerm = '',
    this.studentId = '',
  });

  factory StudentProfile.fromJson(Map<String, dynamic> json) {
    final data = _safeMap(json['data']);
    final src = data.isNotEmpty ? data : json;
    final properties = _safeMap(src['properties']);

    final name = _safeString(src['name']);
    final rollNo = _safeString(src['rollNo']);
    final programme = _safeString(src['programme']);

    final rawBatchName = _safeString(src['batchName']);
    final batchDeptFallback = _safeString(src['department']);
    final batchName = rawBatchName.isNotEmpty ? rawBatchName : batchDeptFallback;

    final rawCurrentSem = _safeString(src['currentSem']);
    final semAcademicFallback = _safeString(src['academicTerm']);
    final currentSem = rawCurrentSem.isNotEmpty ? rawCurrentSem : semAcademicFallback;

    final imageUrl = _safeString(src['image']);

    final rawRegisterNo = _safeString(src['registerNo']);
    final rawRegisterNumber = _safeString(properties['registerNumber']);
    final registerNo = rawRegisterNo.isNotEmpty ? rawRegisterNo : rawRegisterNumber;

    final department = _safeString(src['department']);
    final academicTerm = _safeString(src['academicTermName']);
    final studentId = _safeString(src['studentId'] ?? src['id']);

    return StudentProfile(
      name: name,
      rollNo: rollNo,
      registerNo: registerNo,
      programme: programme,
      batchName: batchName,
      currentSem: currentSem,
      imageUrl: imageUrl,
      registerNumber: rawRegisterNumber.isNotEmpty ? rawRegisterNumber : registerNo,
      department: department,
      academicTerm: academicTerm,
      studentId: studentId,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'rollNo': rollNo,
    'registerNo': registerNo,
    'programme': programme,
    'batchName': batchName,
    'currentSem': currentSem,
    'image': imageUrl,
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
