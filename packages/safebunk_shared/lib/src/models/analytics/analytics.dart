class AnalyticsSummary {
  final int totalClasses;
  final int attended;
  final int missed;
  final double overallPercentage;

  const AnalyticsSummary({
    required this.totalClasses,
    required this.attended,
    required this.missed,
    required this.overallPercentage,
  });

  factory AnalyticsSummary.fromJson(Map<String, dynamic> json) => AnalyticsSummary(
    totalClasses: _i(json['totalClasses']) ?? 0,
    attended: _i(json['attended']) ?? 0,
    missed: _i(json['missed']) ?? 0,
    overallPercentage: _d(json['overallPercentage']) ?? 0.0,
  );

  Map<String, dynamic> toJson() => {
    'totalClasses': totalClasses,
    'attended': attended,
    'missed': missed,
    'overallPercentage': overallPercentage,
  };

  static int? _i(dynamic v) => v is int ? v : (v is double ? v.toInt() : (v is String ? int.tryParse(v) : null));
  static double? _d(dynamic v) => v is double ? v : (v is int ? v.toDouble() : (v is String ? double.tryParse(v) : null));
}

class HourWiseAttendance {
  final String hour;
  final String subjectName;
  final String status;

  const HourWiseAttendance({
    required this.hour,
    required this.subjectName,
    required this.status,
  });

  factory HourWiseAttendance.fromJson(Map<String, dynamic> json) => HourWiseAttendance(
    hour: _s(json['hour']) ?? '',
    subjectName: _s(json['subjectName']) ?? '',
    status: _s(json['status']) ?? '',
  );

  Map<String, dynamic> toJson() => {
    'hour': hour,
    'subjectName': subjectName,
    'status': status,
  };

  static String? _s(dynamic v) => v is String ? v : (v?.toString());
}

class ConsolidatedAnalytics {
  final List<dynamic> subjectWise;
  final List<HourWiseAttendance> hourWise;
  final AnalyticsSummary summary;

  const ConsolidatedAnalytics({
    required this.subjectWise,
    required this.hourWise,
    required this.summary,
  });

  factory ConsolidatedAnalytics.fromJson(Map<String, dynamic> json) {
    final rawHourWise = json['hourWise'] as List? ?? [];
    return ConsolidatedAnalytics(
      subjectWise: json['subjectWise'] as List? ?? [],
      hourWise: rawHourWise
          .map((e) => HourWiseAttendance.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      summary: AnalyticsSummary.fromJson(json['summary'] as Map<String, dynamic>? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
    'subjectWise': subjectWise,
    'hourWise': hourWise.map((h) => h.toJson()).toList(),
    'summary': summary.toJson(),
  };
}
