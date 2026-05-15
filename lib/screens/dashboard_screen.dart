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
    final lastUpdated = ref.watch(lastUpdatedProvider);

    ref.listen(attendanceAnalysisProvider, (_, next) {
      next.whenOrNull(data: (_) {
        ref.read(lastUpdatedProvider.notifier).state = DateTime.now();
      });
    });

    // Build lookup map from official data
    final officialMap = officialAsync.whenOrNull(
      data: (list) {
        final map = <String, double>{};
        for (final s in list) {
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
              padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 16),
              itemCount: items.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _LastUpdatedRow(lastUpdated: lastUpdated);
                }
                final item = items[index - 1];
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
    final String label;
    final Color bg;
    final Color fg;
    if (a.isDanger) {
      label = 'Critical';
      bg = Colors.red.shade50;
      fg = Colors.red.shade800;
    } else if (a.isWarning) {
      label = 'Warning';
      bg = Colors.orange.shade50;
      fg = Colors.orange.shade800;
    } else {
      label = 'Safe';
      bg = Colors.green.shade50;
      fg = Colors.green.shade800;
    }

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
                    color: bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(label,
                    style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 13)),
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

String _formatLastUpdated(DateTime? dt) {
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'Updated just now';
  if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes} min ago';
  if (diff.inHours < 24) return 'Updated ${diff.inHours} hr ago';
  return 'Updated ${dt.day}/${dt.month}/${dt.year}';
}

class _LastUpdatedRow extends StatelessWidget {
  final DateTime? lastUpdated;
  const _LastUpdatedRow({this.lastUpdated});

  @override
  Widget build(BuildContext context) {
    final text = _formatLastUpdated(lastUpdated);
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
      ),
    );
  }
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
