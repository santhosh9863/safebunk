import 'package:flutter_riverpod/flutter_riverpod.dart';

final darkModeProvider = StateProvider<bool>((ref) => false);

final attendanceTargetProvider = StateProvider<double>((ref) => 75);

final attendanceAlertsProvider = StateProvider<bool>((ref) => true);

final lowAttendanceWarningProvider = StateProvider<bool>((ref) => true);

(double danger, double safe, double safest) computeThresholds(double target) {
  if (target == 60) return (60, 60, 75);
  return (60, 75, 90);
}
