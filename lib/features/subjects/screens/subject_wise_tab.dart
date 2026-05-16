import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/calculations/attendance_engine.dart';
import '../../../models/api/subject_wise_attendance_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/subject_wise_attendance_provider.dart';
import '../../settings/providers/settings_providers.dart';

class SubjectWiseTab extends ConsumerStatefulWidget {
  const SubjectWiseTab({super.key});

  @override
  ConsumerState<SubjectWiseTab> createState() => _SubjectWiseTabState();
}

class _SubjectWiseTabState extends ConsumerState<SubjectWiseTab> {
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
        title: const Text('Subject-wise Attendance'),
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: asyncSubjects.when(
          loading: () => ListView(
            children: const [
              _LoadingIndicator(),
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
                  _EmptySubjects(),
                ],
              );
            }

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _SectionHeader(title: 'All Subjects'),
                const SizedBox(height: 8),
                ...subjects.map((s) => _SubjectDetailCard(subject: s, target: target)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SubjectDetailCard extends StatelessWidget {
  final SubjectWiseAttendanceModel subject;
  final double target;

  const _SubjectDetailCard({required this.subject, required this.target});

  @override
  Widget build(BuildContext context) {
    final pct = subject.finalPercentage;
    final (label, bg, fg) = _computeSubjectStatus(pct);

    final safeBunks = AttendanceEngine.calculateSafeBunks(
      subject.effectivePresent,
      subject.totalHours,
    );
    final requiredClasses = AttendanceEngine.calculateRequiredClasses(
      subject.effectivePresent,
      subject.totalHours,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    subject.subjectName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${pct.toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                _StatChip(label: 'Safe Leaves', value: '$safeBunks'),
                const SizedBox(width: 10),
                _StatChip(label: 'Must Attend', value: '$requiredClasses'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  (String, Color, Color) _computeSubjectStatus(double pct) {
    final (danger, safe, safest) = computeThresholds(target);

    if (pct >= safest) return ('SAFEST', Colors.teal.withValues(alpha: 0.15), Colors.teal);
    if (pct >= safe) return ('SAFE', Colors.green.withValues(alpha: 0.15), Colors.green);
    if (pct >= danger) return ('WARNING', Colors.orange.withValues(alpha: 0.15), Colors.orange);
    return ('DANGER', Colors.red.withValues(alpha: 0.15), Colors.red);
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          Text(label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.cloud_off, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            const Text(
              'Failed to load subjects',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySubjects extends StatelessWidget {
  const _EmptySubjects();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.menu_book_outlined, size: 48, color: cs.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text(
                'No subject data available',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Pull down to refresh',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
