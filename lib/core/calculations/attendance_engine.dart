import '../../models/api/daily_attendance_model.dart';
import 'attendance_rules.dart';
import 'attendance_utils.dart';

// ─────────────────────────────────────────────────────────────
//  CENTRAL ATTENDANCE STATUS MAPPING
//  Single source of truth for how raw status values are interpreted.
// ─────────────────────────────────────────────────────────────

enum AttendanceStatus {
  absent('0'),
  present('1'),
  leave('2'),
  dutyLeave('3');

  final String raw;
  const AttendanceStatus(this.raw);

  static AttendanceStatus fromRaw(String raw) {
    return switch (raw) {
      '0' => AttendanceStatus.absent,
      '1' => AttendanceStatus.present,
      '2' => AttendanceStatus.leave,
      '3' => AttendanceStatus.dutyLeave,
      _ => raw.toLowerCase().contains('leave') || raw.toLowerCase().contains('duty')
          ? AttendanceStatus.dutyLeave
          : AttendanceStatus.absent,
    };
  }

  /// Status 1 (Present) and 3 (Duty Leave) count as present.
  bool get countsAsPresent => this == AttendanceStatus.present || this == AttendanceStatus.dutyLeave;

  /// Status 2 (Approved Leave) is excluded from total.
  /// Everything else counts in the denominator.
  bool get countsInTotal => this != AttendanceStatus.leave;
}

// ─────────────────────────────────────────────────────────────
//  SUBJECT ATTENDANCE — aggregated per-subject breakdown
// ─────────────────────────────────────────────────────────────

class SubjectAttendance {
  final String subjectName;
  final int present;
  final int absent;
  final int leave;
  final int dutyLeave;
  final int totalHours;

  const SubjectAttendance({
    required this.subjectName,
    required this.present,
    required this.absent,
    required this.leave,
    required this.dutyLeave,
    required this.totalHours,
  });

  int get effectivePresent => present + dutyLeave;
  int get effectiveTotal => totalHours - leave;
  double get percentage => _calcPct(effectivePresent, effectiveTotal);
  int get safeBunks => AttendanceEngine.calculateSafeBunks(effectivePresent, effectiveTotal);
  int get classesNeeded => AttendanceEngine.calculateRequiredClasses(effectivePresent, effectiveTotal);

  static double _calcPct(int p, int t) {
    if (t <= 0) return t == 0 ? 100.0 : 0.0;
    return double.parse(((p / t) * 100).toStringAsFixed(2));
  }
}

// ─────────────────────────────────────────────────────────────
//  ATTENDANCE STATS — standard calculation output
// ─────────────────────────────────────────────────────────────

class AttendanceStats {
  final double percentage;
  final int safeBunks;
  final int classesNeeded;
  final bool isDanger;
  final bool isWarning;
  final bool isSafe;
  final int presentHours;
  final int totalHours;
  final int dutyLeaveHours;
  final double attendanceWithoutDutyLeave;

  const AttendanceStats({
    required this.percentage,
    required this.safeBunks,
    required this.classesNeeded,
    required this.isDanger,
    required this.isWarning,
    required this.isSafe,
    required this.presentHours,
    required this.totalHours,
    required this.dutyLeaveHours,
    required this.attendanceWithoutDutyLeave,
  });
}

// ─────────────────────────────────────────────────────────────
//  CENTRAL ATTENDANCE ENGINE
//  ALL attendance math lives HERE and ONLY here.
// ─────────────────────────────────────────────────────────────

class AttendanceEngine {
  AttendanceEngine._();

  /// Aggregate a list of daily records into SubjectAttendance per subject.
  static List<SubjectAttendance> aggregate(List<DailyAttendanceModel> records) {
    final Map<String, _Counts> map = {};

    for (final r in records) {
      final name = r.subjectName.isEmpty ? 'Unknown' : r.subjectName;
      final agg = map.putIfAbsent(name, () => _Counts());

      final status = AttendanceStatus.fromRaw(r.attendanceStatus);
      agg.total++;
      if (status == AttendanceStatus.present) agg.present++;
      else if (status == AttendanceStatus.absent) agg.absent++;
      else if (status == AttendanceStatus.leave) agg.leave++;
      else if (status == AttendanceStatus.dutyLeave) agg.dutyLeave++;
    }

    final result = map.entries.map((e) {
      final a = e.value;
      final subj = SubjectAttendance(
        subjectName: e.key,
        present: a.present,
        absent: a.absent,
        leave: a.leave,
        dutyLeave: a.dutyLeave,
        totalHours: a.total,
      );
      print('[ENGINE] "${subj.subjectName}" — '
          'P:${subj.present} A:${subj.absent} L:${subj.leave} DL:${subj.dutyLeave} '
          'Total:${subj.totalHours} '
          'EffP:${subj.effectivePresent} EffT:${subj.effectiveTotal} '
          '${subj.percentage.toStringAsFixed(1)}% '
          'Bunks:${subj.safeBunks} Needed:${subj.classesNeeded}');
      return subj;
    }).toList();

    print('[ENGINE] Aggregated ${result.length} subjects from ${records.length} records');
    return result;
  }

  /// Compute standardized AttendanceStats for a subject.
  static AttendanceStats computeStats(SubjectAttendance subj) {
    final p = AttendanceUtils.clampIntToZero(subj.effectivePresent);
    final t = AttendanceUtils.clampIntToZero(subj.effectiveTotal);
    final dl = subj.dutyLeave;

    final percentage = _calculatePercentage(p, t);
    final percentageWithoutDL = _calculatePercentageWithoutDutyLeave(p, t, dl);
    final safeBunks = AttendanceEngine.calculateSafeBunks(p, t);
    final classesNeeded = AttendanceEngine.calculateRequiredClasses(p, t);

    return AttendanceStats(
      percentage: percentage,
      safeBunks: safeBunks,
      classesNeeded: classesNeeded,
      isDanger: percentage < AttendanceRules.dangerAttendance,
      isWarning: percentage >= AttendanceRules.dangerAttendance &&
          percentage < AttendanceRules.warningAttendance,
      isSafe: percentage >= AttendanceRules.warningAttendance,
      presentHours: p,
      totalHours: t,
      dutyLeaveHours: dl,
      attendanceWithoutDutyLeave: percentageWithoutDL,
    );
  }

  // ── Formula: percentage ──

  static double _calculatePercentage(int present, int total) {
    if (total == 0) return 0.0;
    return AttendanceUtils.roundPercentage(
      AttendanceUtils.clampPercentage(
        AttendanceUtils.safeDivide(present.toDouble(), total.toDouble()) * 100,
      ),
    );
  }

  static double _calculatePercentageWithoutDutyLeave(int present, int total, int dutyLeave) {
    final adjusted = total - dutyLeave;
    if (adjusted <= 0) return 100.0;
    return AttendanceUtils.roundPercentage(
      AttendanceUtils.clampPercentage(
        AttendanceUtils.safeDivide(present.toDouble(), adjusted.toDouble()) * 100,
      ),
    );
  }

  // ── Formula: safe bunks ──
  //  P / (T + x) >= minimum  →  x = floor(P / m - T)

  static int calculateSafeBunks(int present, int total) {
    if (total == 0) return 0;
    final m = AttendanceRules.minimumAttendance / 100;
    final ratio = present / m - total;
    if (ratio <= 0) return 0;
    return ratio.floor();
  }

  // ── Formula: required classes ──
  //  (P + x) / (T + x) >= minimum  →  x = ceil((Tm - P) / (1 - m))

  static int calculateRequiredClasses(int present, int total) {
    if (total == 0) return 0;
    final m = AttendanceRules.minimumAttendance / 100;
    final needed = (total * m - present) / (1 - m);
    if (needed <= 0) return 0;
    return needed.ceil();
  }

  // ── Central status helpers ──

  static bool countsAsPresent(String rawStatus) => AttendanceStatus.fromRaw(rawStatus).countsAsPresent;
  static bool countsInTotal(String rawStatus) => AttendanceStatus.fromRaw(rawStatus).countsInTotal;
}

class _Counts {
  int total = 0;
  int present = 0;
  int absent = 0;
  int leave = 0;
  int dutyLeave = 0;
}
