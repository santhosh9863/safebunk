import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/attendance_analysis_provider.dart';
import '../providers/attendance_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/subject_wise_attendance_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysisAsync = ref.watch(attendanceAnalysisProvider);
    final officialAsync = ref.watch(subjectWiseAttendanceProvider);

    // Build lookup map from official data
    final officialMap = officialAsync.whenOrNull(
      data: (list) {
        final map = <String, double>{};
        for (final s in list) {
          final norm = _normalize(s.subjectName);
          print('[MATCH_DEBUG] API name="${s.subjectName}" norm="$norm"');
          map[s.subjectName] = s.finalPercentage;
        }
        return map;
      },
    ) ?? <String, double>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeBunk'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(subjectAttendanceProvider);
              ref.invalidate(subjectWiseAttendanceProvider);
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: analysisAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: e.toString().replaceFirst('Exception: ', ''),
          onRetry: () {
            ref.invalidate(subjectAttendanceProvider);
            ref.invalidate(subjectWiseAttendanceProvider);
          },
        ),
        data: (items) {
          if (items.isEmpty) {
            return _EmptyView(
              onRetry: () {
                ref.invalidate(subjectAttendanceProvider);
                ref.invalidate(subjectWiseAttendanceProvider);
              },
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(subjectAttendanceProvider);
              ref.invalidate(subjectWiseAttendanceProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final normCard = _normalize(item.subjectName);
                double? officialPct;
                if (officialMap.containsKey(item.subjectName)) {
                  officialPct = officialMap[item.subjectName];
                } else {
                  for (final entry in officialMap.entries) {
                    if (_normalize(entry.key) == normCard) {
                      officialPct = entry.value;
                      break;
                    }
                  }
                }
                final pctStr = officialPct?.toStringAsFixed(1) ?? '--';
                print('[MATCH_DEBUG] Card="${item.subjectName}" norm="$normCard" Official=$pctStr');
                return _SubjectCard(item: item, officialPercentage: officialPct);
              },
            ),
          );
        },
      ),
    );
  }
}

/// Normalize subject name for lookup comparison only.
String _normalize(String s) {
  return s
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('( ', '(')
      .replaceAll(' )', ')')
      .replaceAll(' - ', '-')
      .trim();
}

class _SubjectCard extends StatelessWidget {
  final AttendanceAnalysisItem item;
  final double? officialPercentage;

  const _SubjectCard({required this.item, this.officialPercentage});

  @override
  Widget build(BuildContext context) {
    final a = item.analysis;
    final label = a.isSafe ? 'SAFE' : (a.isWarning ? 'WARNING' : 'DANGER');
    final color = a.isSafe ? Colors.green : (a.isWarning ? Colors.orange : Colors.red);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(item.subjectName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(label,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _col('Attendance', '${a.percentage.toStringAsFixed(1)}%'),
                const SizedBox(width: 24),
                _col('Safe Bunks', a.safeBunks.toString()),
                const SizedBox(width: 24),
                _col('Needed', a.requiredClasses.toString()),
              ],
            ),
            if (officialPercentage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Text('Official: ', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    Text('${officialPercentage!.toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
                        color: Colors.green[700])),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Official: --',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400])),
              ),
            if (a.totalHours > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${a.presentHours}/${a.totalHours} classes',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _col(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    ],
  );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text('Failed to load attendance',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: onRetry,
            icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ],
      ),
    ),
  );
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onRetry;
  const _EmptyView({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.event_note_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('No attendance data available',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Pull down to refresh or tap retry.',
            style: TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 24),
          OutlinedButton.icon(onPressed: onRetry,
            icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ],
      ),
    ),
  );
}
