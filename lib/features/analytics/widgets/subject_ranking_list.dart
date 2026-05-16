import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/api/subject_wise_attendance_model.dart';
import '../../settings/providers/settings_providers.dart';

class SubjectRankingList extends ConsumerWidget {
  final List<SubjectWiseAttendanceModel> subjects;

  const SubjectRankingList({super.key, required this.subjects});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (subjects.isEmpty) return const SizedBox.shrink();

    final target = ref.watch(attendanceTargetProvider);
    final (danger, _, _) = computeThresholds(target);

    final sorted = List<SubjectWiseAttendanceModel>.from(subjects)
      ..sort((a, b) => b.finalPercentage.compareTo(a.finalPercentage));

    final dangerSubjects = sorted.where((s) => s.finalPercentage < danger).toList();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Subject Ranking',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Sorted by attendance percentage',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ...List.generate(sorted.length, (i) {
              final subject = sorted[i];
              final rank = i + 1;
            return _RankItem(
              rank: rank,
              subjectName: subject.subjectName,
              percentage: subject.finalPercentage,
              target: target,
              isLast: i == sorted.length - 1,
            );
            }),
            if (dangerSubjects.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 20, color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${dangerSubjects.length} subject${dangerSubjects.length == 1 ? '' : 's'} below ${danger.round()}% threshold',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RankItem extends StatelessWidget {
  final int rank;
  final String subjectName;
  final double percentage;
  final bool isLast;
  final double target;

  const _RankItem({
    required this.rank,
    required this.subjectName,
    required this.percentage,
    required this.isLast,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) = _computeStatus(percentage);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: _RankBadge(rank: rank),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  subjectName,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 56,
                child: Text(
                  '${percentage.toStringAsFixed(1)}%',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isLast) Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
      ],
    );
  }

  (String, Color) _computeStatus(double pct) {
    final (danger, safe, safest) = computeThresholds(target);

    if (pct >= safest) return ('SAFEST', Colors.teal);
    if (pct >= safe) return ('SAFE', Colors.green);
    if (pct >= danger) return ('WARNING', Colors.orange);
    return ('DANGER', Colors.red);
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;

  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color bgColor;
    Color fgColor;

    if (rank == 1) {
      bgColor = Colors.amber;
      fgColor = Colors.white;
    } else if (rank == 2) {
      bgColor = Colors.grey.shade400;
      fgColor = Colors.white;
    } else if (rank == 3) {
      bgColor = Colors.brown.shade300;
      fgColor = Colors.white;
    } else {
      bgColor = cs.surfaceContainerHighest;
      fgColor = cs.onSurfaceVariant;
    }

    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: fgColor,
        ),
      ),
    );
  }
}
