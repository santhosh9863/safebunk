import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/auth_provider.dart';
import '../../../providers/subject_wise_attendance_provider.dart';
import '../../settings/providers/settings_providers.dart';
import '../widgets/analytics_summary_card.dart';
import '../widgets/attendance_bar_chart.dart';
import '../widgets/subject_ranking_list.dart';

class AnalyticsTab extends ConsumerStatefulWidget {
  const AnalyticsTab({super.key});

  @override
  ConsumerState<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends ConsumerState<AnalyticsTab> {
  Future<void> _onRefresh() async {
    ref.read(cacheManagerProvider).clearAll();
    ref.invalidate(subjectWiseAttendanceProvider);
  }

  @override
  Widget build(BuildContext context) {
    final asyncSubjects = ref.watch(subjectWiseAttendanceProvider);
    final target = ref.watch(attendanceTargetProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: asyncSubjects.when(
          loading: () => ListView(
            children: const [
              SizedBox(height: 80),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (e, _) => ListView(
            children: [
              _ErrorCard(
                message: e.toString().replaceFirst('Exception: ', ''),
                onRetry: _onRefresh,
              ),
            ],
          ),
          data: (subjects) {
            if (subjects.isEmpty) {
              return ListView(
                children: const [
                  _EmptyAnalytics(),
                ],
              );
            }

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                AnalyticsSummaryCard(subjects: subjects, target: target),
                const SizedBox(height: 16),
                AttendanceBarChart(subjects: subjects, target: target),
                const SizedBox(height: 16),
                SubjectRankingList(subjects: subjects),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'Failed to load analytics',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyAnalytics extends StatelessWidget {
  const _EmptyAnalytics();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.analytics_outlined,
                size: 64,
                color: theme.colorScheme.primary.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 20),
              Text(
                'No analytics data',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Attendance data will appear here once available',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 6),
              Text(
                'Pull down to refresh',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
