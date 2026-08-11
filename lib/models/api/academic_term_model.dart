class AcademicTermModel {
  final String termId;
  final String termName;
  final String startDate;
  final String endDate;

  const AcademicTermModel({
    required this.termId,
    required this.termName,
    this.startDate = '',
    this.endDate = '',
  });

  factory AcademicTermModel.fromJson(Map<String, dynamic> json) {
    return AcademicTermModel(
      termId: _s(json['termId']) ?? _s(json['id']) ?? '',
      termName: _s(json['termName']) ?? _s(json['name']) ?? '',
      startDate: _s(json['startDate']) ?? _s(json['start_date']) ?? '',
      endDate: _s(json['endDate']) ?? _s(json['end_date']) ?? '',
    );
  }

  static String? _s(dynamic v) => v is String ? v : (v?.toString());
}

class CurrentTerm {
  final String termId;
  final String termName;
  final String startDate;
  final String endDate;
  final String reason;

  const CurrentTerm({
    required this.termId,
    this.termName = '',
    this.startDate = '',
    this.endDate = '',
    this.reason = '',
  });
}
