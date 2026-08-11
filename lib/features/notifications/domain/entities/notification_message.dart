/// A ready-to-display notification message produced by the content service.
class NotificationMessage {
  final String title;
  final String body;

  const NotificationMessage({required this.title, required this.body});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationMessage &&
          title == other.title &&
          body == other.body;

  @override
  int get hashCode => Object.hash(title, body);

  @override
  String toString() => '$title\n$body';
}
