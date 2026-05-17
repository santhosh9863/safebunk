import '../../../core/calculations/attendance_engine.dart';
import '../../../core/calculations/attendance_utils.dart';
import '../../settings/providers/settings_providers.dart';

class SubjectEntry {
  final String displayName;
  final int presentHours;
  final int totalHours;

  const SubjectEntry({
    required this.displayName,
    required this.presentHours,
    required this.totalHours,
  });
}

class SimulationResult {
  final double currentPercentage;
  final double predictedPercentage;
  final int currentSafeBunks;
  final int predictedSafeBunks;
  final bool isDanger;
  final bool isWarning;

  const SimulationResult({
    required this.currentPercentage,
    required this.predictedPercentage,
    required this.currentSafeBunks,
    required this.predictedSafeBunks,
    required this.isDanger,
    required this.isWarning,
  });

  bool get isSafe => !isDanger && !isWarning;

  double get difference =>
      AttendanceUtils.roundPercentage(predictedPercentage - currentPercentage);
}

class AttendanceSimulationHelper {
  AttendanceSimulationHelper._();

  static SimulationResult simulate({
    required int currentPresent,
    required int currentTotal,
    required int additionalPresent,
    required int additionalTotal,
    double target = 75,
  }) {
    final newPresent = currentPresent + additionalPresent;
    final newTotal = currentTotal + additionalTotal;

    final currentPct = _computePercentage(currentPresent, currentTotal);
    final predictedPct = _computePercentage(newPresent, newTotal);

    final currentBunks =
        AttendanceEngine.calculateSafeBunks(currentPresent, currentTotal);
    final predictedBunks =
        AttendanceEngine.calculateSafeBunks(newPresent, newTotal);

    final (danger, safe, _) = computeThresholds(target);

    return SimulationResult(
      currentPercentage: currentPct,
      predictedPercentage: predictedPct,
      currentSafeBunks: currentBunks,
      predictedSafeBunks: predictedBunks,
      isDanger: predictedPct < danger,
      isWarning: predictedPct >= danger && predictedPct < safe,
    );
  }

  static double _computePercentage(int present, int total) {
    if (total <= 0) return 0.0;
    return AttendanceUtils.roundPercentage(
      AttendanceUtils.clampPercentage(
        AttendanceUtils.safeDivide(present.toDouble(), total.toDouble()) * 100,
      ),
    );
  }

  static int computeSafeBunks(int present, int total) {
    return AttendanceEngine.calculateSafeBunks(present, total);
  }

  static double computePercentage(int present, int total) {
    return _computePercentage(present, total);
  }

  static double computePercentageDiff(double current, double predicted) {
    return AttendanceUtils.roundPercentage(predicted - current);
  }
}

class PercentageComputer {
  PercentageComputer._();

  static double compute(int present, int total) {
    return AttendanceSimulationHelper.computePercentage(present, total);
  }

  static double diff(double current, double predicted) {
    return AttendanceSimulationHelper.computePercentageDiff(current, predicted);
  }
}

class SafeBunksComputer {
  SafeBunksComputer._();

  static int compute(int present, int total) {
    return AttendanceSimulationHelper.computeSafeBunks(present, total);
  }
}

class ThresholdComputer {
  ThresholdComputer._();

  static (double danger, double safe, double safest) compute(double target) {
    return computeThresholds(target);
  }
}
