/// A minimal, server-authorized report change notification.
///
/// The payload intentionally contains no description, photo, attachment URL,
/// reporter identity, or staff identity. The REST API remains the source of
/// truth; this event only tells the app which authorized providers to refresh.
class ReportRealtimeEvent {
  final String eventId;
  final String reportId;
  final String code;
  final String status;
  final String change;
  final DateTime? occurredAt;

  const ReportRealtimeEvent({
    required this.eventId,
    required this.reportId,
    required this.code,
    required this.status,
    required this.change,
    this.occurredAt,
  });

  /// Parses a Socket.IO payload defensively. Malformed or partial payloads are
  /// ignored rather than triggering an unbounded refresh.
  static ReportRealtimeEvent? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);

    String? requiredString(String key) {
      final value = json[key]?.toString().trim() ?? '';
      return value.isEmpty ? null : value;
    }

    final eventId = requiredString('eventId');
    final reportId = requiredString('reportId');
    final code = requiredString('code');
    final status = requiredString('status');
    final change = requiredString('change');
    if (eventId == null ||
        reportId == null ||
        code == null ||
        status == null ||
        change == null) {
      return null;
    }

    final rawOccurredAt = json['occurredAt']?.toString();
    return ReportRealtimeEvent(
      eventId: eventId,
      reportId: reportId,
      code: code,
      status: status,
      change: change,
      occurredAt: rawOccurredAt == null
          ? null
          : DateTime.tryParse(rawOccurredAt),
    );
  }
}
