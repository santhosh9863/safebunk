import '../../domain/report_enums.dart';

/// Domain model for a campus issue report returned by the PULSE backend.
///
/// The backend returns the same shape for `POST /api/reports`,
/// `GET /api/reports/my` and `GET /api/reports/:id` (a report summary).
/// `description` / `imageUrl` are optional so a future slimmer summary payload
/// still parses without crashing.
class ReportModel {
  final String id;
  final String code;
  final String title;
  final String description;
  final String? category;
  final String? location;
  final String? imageUrl;
  final String priority;
  final String status;
  final String? assignedDepartment;
  final String? aiCategory;
  final String? aiPriority;
  final double? aiConfidence;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? resolvedAt;

  const ReportModel({
    required this.id,
    required this.code,
    required this.title,
    required this.description,
    required this.category,
    required this.location,
    required this.imageUrl,
    required this.priority,
    required this.status,
    required this.assignedDepartment,
    required this.aiCategory,
    required this.aiPriority,
    required this.aiConfidence,
    required this.createdAt,
    required this.updatedAt,
    required this.resolvedAt,
  });

  factory ReportModel.fromJson(Map<String, dynamic> json) {
    return ReportModel(
      id: _s(json['id']) ?? '',
      code: _s(json['code']) ?? '',
      title: _s(json['title']) ?? '',
      description: _s(json['description']) ?? '',
      category: _s(json['category']),
      location: _s(json['location']),
      imageUrl: _s(json['imageUrl']),
      priority: _s(json['priority']) ?? 'MEDIUM',
      status: _s(json['status']) ?? 'SUBMITTED',
      assignedDepartment: _s(json['assignedDepartment']),
      aiCategory: _s(json['aiCategory']),
      aiPriority: _s(json['aiPriority']),
      aiConfidence: _d(json['aiConfidence']),
      createdAt: _dt(json['createdAt']) ?? DateTime.now(),
      updatedAt: _dt(json['updatedAt']) ?? DateTime.now(),
      resolvedAt: _dt(json['resolvedAt']),
    );
  }

  ReportStatus get statusEnum => ReportStatus.fromApi(status);
  ReportPriority get priorityEnum => ReportPriority.fromApi(priority);

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'title': title,
        'description': description,
        'category': category,
        'location': location,
        'imageUrl': imageUrl,
        'priority': priority,
        'status': status,
        'assignedDepartment': assignedDepartment,
        'aiCategory': aiCategory,
        'aiPriority': aiPriority,
        'aiConfidence': aiConfidence,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'resolvedAt': resolvedAt?.toIso8601String(),
      };

  static String? _s(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

  static double? _d(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static DateTime? _dt(dynamic v) {
    if (v is DateTime) return v.toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }
}
