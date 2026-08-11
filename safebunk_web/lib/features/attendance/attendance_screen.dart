import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safebunk_shared/safebunk_shared.dart';


class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncAttendance = ref.watch(subjectAttendanceProvider);
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(subjectAttendanceProvider),
      child: asyncAttendance.when(
        data: (subjects) {
          if (subjects.isEmpty) {
            return const Center(child: Text('No attendance data available'));
          }

          final overall = subjects.isEmpty
              ? 0.0
              : subjects.map((s) => s.finalPercentage).reduce((a, b) => a + b) / subjects.length;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text('Overall Attendance', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('${overall.toStringAsFixed(1)}%',
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _colorForPercentage(overall, theme),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ...subjects.map((sub) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(sub.subjectName, style: theme.textTheme.titleSmall),
                            const SizedBox(height: 4),
                            Text('${sub.attendedHours}/${sub.totalHours} hours',
                              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${sub.finalPercentage.toStringAsFixed(1)}%',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _colorForPercentage(sub.finalPercentage, theme),
                        ),
                      ),
                    ],
                  ),
                ),
              )),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Color _colorForPercentage(double pct, ThemeData theme) {
    if (pct >= 75) return Colors.green;
    if (pct >= 60) return Colors.orange;
    return theme.colorScheme.error;
  }
}
