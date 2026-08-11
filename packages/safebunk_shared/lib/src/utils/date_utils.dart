class DateHelper {
  DateHelper._();

  static String formatDisplay(String dateStr) {
    if (dateStr.length < 10) return dateStr;
    final parts = dateStr.split('-');
    if (parts.length != 3) return dateStr;
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final month = int.tryParse(parts[1]) ?? 0;
    final monthName = month > 0 && month <= 12 ? months[month] : parts[1];
    return '${monthName} ${parts[2]}, ${parts[0]}';
  }

  static String dayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  static String today() {
    final now = DateTime.now();
    return '${now.year}-${_pad(now.month)}-${_pad(now.day)}';
  }

  static String weekStart(String dateStr) {
    final date = _parse(dateStr);
    if (date == null) return dateStr;
    final weekday = date.weekday;
    final monday = date.subtract(Duration(days: weekday - 1));
    return '${monday.year}-${_pad(monday.month)}-${_pad(monday.day)}';
  }

  static String weekEnd(String dateStr) {
    final date = _parse(dateStr);
    if (date == null) return dateStr;
    final weekday = date.weekday;
    final sunday = date.add(Duration(days: 7 - weekday));
    return '${sunday.year}-${_pad(sunday.month)}-${_pad(sunday.day)}';
  }

  static DateTime? _parse(String dateStr) {
    if (dateStr.length < 10) return null;
    final parts = dateStr.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
