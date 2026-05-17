class AttendanceUtils {
  AttendanceUtils._();

  static double safeDivide(double numerator, double denominator) {
    if (denominator == 0) return 0.0;
    return numerator / denominator;
  }

  static double roundPercentage(double value) {
    return (value * 100).roundToDouble() / 100;
  }

  static double clampNegative(double value) {
    return value < 0 ? 0.0 : value;
  }

  static double clampPercentage(double value) {
    if (value < 0) return 0.0;
    if (value > 100) return 100.0;
    return value;
  }

  static bool isValidPercentage(double value) {
    return value >= 0 && value <= 100;
  }

  static int clampIntToZero(int value) {
    return value < 0 ? 0 : value;
  }

  static String cleanSubjectName(String? subjectName) {
    if (subjectName == null || subjectName.isEmpty) return '';
    return subjectName.replaceFirst(RegExp(r'\s*\([^)]*\)$'), '').trim();
  }
}
