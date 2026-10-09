/// Backend response for `POST /api/reports/attachments`.
///
/// [url] is a backend-relative path (e.g. `/api/reports/attachments/<id>`)
/// that must be resolved against the PULSE backend base URL and fetched with
/// the authenticated Bearer token — it is not a public URL.
class ReportAttachment {
  final String id;
  final String url;
  final String contentType;
  final int size;
  final DateTime? createdAt;

  const ReportAttachment({
    required this.id,
    required this.url,
    required this.contentType,
    required this.size,
    this.createdAt,
  });

  factory ReportAttachment.fromJson(Map<String, dynamic> json) {
    return ReportAttachment(
      id: _s(json['id']) ?? '',
      url: _s(json['url']) ?? '',
      contentType: _s(json['contentType']) ?? 'application/octet-stream',
      size: _i(json['size']),
      createdAt: _dt(json['createdAt']),
    );
  }

  static String? _s(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

  static int _i(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static DateTime? _dt(dynamic v) {
    if (v is DateTime) return v.toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }
}
