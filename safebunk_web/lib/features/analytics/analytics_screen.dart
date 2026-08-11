import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safebunk_shared/safebunk_shared.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncAnalytics = ref.watch(analyticsProvider);
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(analyticsProvider),
      child: asyncAnalytics.when(
        data: (analytics) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('Attendance Summary', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 16),
                    _StatRow(label: 'Total Classes', value: analytics.summary.totalClasses.toString()),
                    _StatRow(label: 'Attended', value: analytics.summary.attended.toString()),
                    _StatRow(label: 'Missed', value: analytics.summary.missed.toString()),
                    const Divider(),
                    _StatRow(
                      label: 'Overall Percentage',
                      value: '${analytics.summary.overallPercentage.toStringAsFixed(1)}%',
                      valueColor: analytics.summary.overallPercentage >= 75
                          ? Colors.green
                          : analytics.summary.overallPercentage >= 60
                              ? Colors.orange
                              : theme.colorScheme.error,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Subject-wise', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...analytics.subjectWise.map((sub) {
              final map = sub as Map<String, dynamic>;
              final name = map['subjectName'] as String? ?? map['courseName'] as String? ?? 'Unknown';
              final total = (map['totalHours'] as num?)?.toInt() ?? (map['totalAttendance'] as num?)?.toInt() ?? 0;
              final attended = (map['attendedHours'] as num?)?.toInt() ?? (map['totalPresentMarkHour'] as num?)?.toInt() ?? 0;
              final pct = total > 0 ? (attended / total * 100) : 0.0;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: total > 0 ? attended / total : 0,
                        color: pct >= 75 ? Colors.green : pct >= 60 ? Colors.orange : theme.colorScheme.error,
                      ),
                      const SizedBox(height: 4),
                      Text('$attended/$total (${pct.toStringAsFixed(1)}%)',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StatRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: valueColor,
          )),
        ],
      ),
    );
  }
}
