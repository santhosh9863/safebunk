import 'package:flutter/material.dart';

import '../../../core/calculations/attendance_utils.dart';
import '../../../models/api/subject_wise_attendance_model.dart';
import '../../settings/providers/settings_providers.dart';

class AnalyticsSummaryCard extends StatelessWidget {
  final List<SubjectWiseAttendanceModel> subjects;
  final double target;

  const AnalyticsSummaryCard({super.key, required this.subjects, required this.target});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (subjects.isEmpty) return const SizedBox.shrink();

    final (danger, safe, _) = computeThresholds(target);
    final totalSubjects = subjects.length;
    final overallAvg = subjects.fold(0.0, (sum, s) => sum + s.finalPercentage) / totalSubjects;
    final highest = subjects.reduce((a, b) => a.finalPercentage > b.finalPercentage ? a : b);
    final lowest = subjects.reduce((a, b) => a.finalPercentage < b.finalPercentage ? a : b);
    final dangerCount = subjects.where((s) => s.finalPercentage < danger).length;
    final safeCount = subjects.where((s) => s.finalPercentage >= safe).length;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Summary',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _SummaryTile(
                  label: 'Average',
                  value: '${overallAvg.toStringAsFixed(1)}%',
                  color: _avgColor(overallAvg),
                  icon: Icons.trending_up,
                ),
                const SizedBox(width: 12),
                _SummaryTile(
                  label: 'Subjects',
                  value: '$totalSubjects',
                  color: theme.colorScheme.primary,
                  icon: Icons.book,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _HighlightRow(
              icon: Icons.arrow_upward,
              iconColor: Colors.green,
              label: 'Highest',
              detail: '${AttendanceUtils.cleanSubjectName(highest.subjectName)} (${highest.finalPercentage.toStringAsFixed(1)}%)',
            ),
            const SizedBox(height: 8),
            _HighlightRow(
              icon: Icons.arrow_downward,
              iconColor: lowest.finalPercentage < danger
                  ? Colors.red
                  : lowest.finalPercentage < safe
                      ? Colors.orange
                      : Colors.green,
              label: 'Lowest',
              detail: '${AttendanceUtils.cleanSubjectName(lowest.subjectName)} (${lowest.finalPercentage.toStringAsFixed(1)}%)',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatusChip(
                  label: '$safeCount Safe',
                  color: Colors.green.withValues(alpha: 0.15),
                  textColor: Colors.green,
                ),
                const SizedBox(width: 8),
                _StatusChip(
                  label: '${totalSubjects - safeCount - dangerCount} Warning',
                  color: Colors.orange.withValues(alpha: 0.15),
                  textColor: Colors.orange,
                ),
                const SizedBox(width: 8),
                _StatusChip(
                  label: '$dangerCount Danger',
                  color: Colors.red.withValues(alpha: 0.15),
                  textColor: Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _avgColor(double avg) {
    final (danger, safe, _) = computeThresholds(target);
    if (avg < danger) return Colors.red;
    if (avg < safe) return Colors.orange;
    return Colors.green;
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String detail;

  const _HighlightRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            detail,
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;

  const _StatusChip({
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
