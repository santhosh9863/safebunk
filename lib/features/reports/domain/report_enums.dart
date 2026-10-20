/// Pure Dart enums mirroring the PULSE backend Reports state machine.
/// Keep this file free of Flutter imports so it can be unit-tested directly.
///
/// Backend values:
///   SUBMITTED -> ASSIGNED -> IN_PROGRESS -> RESOLVED
///   SUBMITTED / ASSIGNED / IN_PROGRESS -> REJECTED (admin only, with reason)
enum ReportStatus {
  submitted('SUBMITTED', 'Submitted'),
  assigned('ASSIGNED', 'Assigned'),
  inProgress('IN_PROGRESS', 'In Progress'),
  resolved('RESOLVED', 'Resolved'),
  rejected('REJECTED', 'Rejected');

  const ReportStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static ReportStatus fromApi(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    return ReportStatus.values.firstWhere(
      (s) => s.apiValue == normalized,
      orElse: () => ReportStatus.submitted,
    );
  }

  bool get isTerminal =>
      this == ReportStatus.resolved || this == ReportStatus.rejected;
  bool get isOpen => !isTerminal;
}

/// Issue priority. Phase 1 has no priority prediction (no ML) — the student
/// picks it explicitly and the backend defaults to MEDIUM.
enum ReportPriority {
  low('LOW', 'Low'),
  medium('MEDIUM', 'Medium'),
  high('HIGH', 'High'),
  critical('CRITICAL', 'Critical');

  const ReportPriority(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static ReportPriority fromApi(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    return ReportPriority.values.firstWhere(
      (p) => p.apiValue == normalized,
      orElse: () => ReportPriority.medium,
    );
  }
}
