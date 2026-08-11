import '../enums/notification_type.dart';

/// Domain-level reason WHY a notification should exist.
///
/// Contains DATA only — never wording. The content service turns an event
/// into a user-facing message.
class NotificationEvent {
  final NotificationType type;
  final String? subjectName;
  final double? attendancePercentage;
  final double? previousPercentage;
  final int? safeBunks;
  final Map<String, dynamic> metadata;

  const NotificationEvent({
    required this.type,
    this.subjectName,
    this.attendancePercentage,
    this.previousPercentage,
    this.safeBunks,
    this.metadata = const {},
  });

  @override
  String toString() => 'NotificationEvent(${type.name}, '
      'subject=$subjectName, pct=$attendancePercentage, '
      'prev=$previousPercentage, safeBunks=$safeBunks)';
}
