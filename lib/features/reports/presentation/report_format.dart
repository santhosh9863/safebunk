/// Small, dependency-free date formatting helpers (the app does not depend on
/// `intl`). All timestamps arrive as UTC and are converted to local time by the
/// model before reaching these helpers.
String formatRelativeTime(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(time);

  if (diff.isNegative) return 'Just now';
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatDate(time);
}

String formatDate(DateTime time) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final d = time.day.toString().padLeft(2, '0');
  final m = months[time.month - 1];
  return '$d $m ${time.year}';
}

String formatDateTime(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final min = time.minute.toString().padLeft(2, '0');
  return '${formatDate(time)} · $h:$min';
}
