/// A single entry in a report's status/activity history.
///
/// The backend strips internal progress notes and actor identities from the
/// student-facing timeline; staff/admin responses include the full history.
/// Parsing is intentionally tolerant so one unexpected event type does not
/// prevent the report from rendering.
enum ReportEventType {
  submitted('SUBMITTED', 'Submitted'),
  assigned('ASSIGNED', 'Assigned'),
  reassigned('REASSIGNED', 'Reassigned'),
  inProgress('IN_PROGRESS', 'Work started'),
  progressNote('PROGRESS_NOTE', 'Progress note'),
  resolved('RESOLVED', 'Resolved'),
  rejected('REJECTED', 'Rejected'),
  unknown('UNKNOWN', 'Update');

  const ReportEventType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static ReportEventType fromApi(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    return ReportEventType.values.firstWhere(
      (event) => event.apiValue == normalized,
      orElse: () => ReportEventType.unknown,
    );
  }
}

class ReportEventModel {
  final String id;
  final String type;
  final String actorRole;
  final String? remark;
  final DateTime createdAt;

  const ReportEventModel({
    required this.id,
    required this.type,
    required this.actorRole,
    required this.remark,
    required this.createdAt,
  });

  ReportEventType get typeEnum => ReportEventType.fromApi(type);

  factory ReportEventModel.fromJson(Map<String, dynamic> json) {
    return ReportEventModel(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      actorRole: json['actorRole']?.toString() ?? '',
      remark: _nullableString(json['remark']),
      createdAt:
          _parseDate(json['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'actorRole': actorRole,
    'remark': remark,
    'createdAt': createdAt.toIso8601String(),
  };

  static String? _nullableString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is DateTime) return value.toLocal();
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }
}
