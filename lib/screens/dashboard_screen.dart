import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/calculations/attendance_engine.dart';
import '../core/calculations/attendance_utils.dart';
import '../features/profile/controllers/profile_controller.dart';
import '../features/profile/models/student_profile.dart';
import '../models/api/subject_wise_attendance_model.dart';
import '../providers/attendance_analysis_provider.dart';
import '../providers/attendance_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/subject_wise_attendance_provider.dart';
import '../features/settings/providers/settings_providers.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _profileInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initProfile());
  }

  Future<void> _initProfile() async {
    if (_profileInitialized) return;
    _profileInitialized = true;
    final sessionManager = ref.read(sessionManagerProvider);
    final studentId = await sessionManager.getStudentId();
    if (studentId != null && studentId.isNotEmpty) {
      ref.read(profileControllerProvider.notifier).fetchProfile(studentId);
    }
  }

  Future<void> _onRefresh() async {
    ref.read(cacheManagerProvider).clearAll();
    ref.invalidate(subjectAttendanceProvider);
    ref.invalidate(subjectWiseAttendanceProvider);
    final sessionManager = ref.read(sessionManagerProvider);
    final studentId = await sessionManager.getStudentId();
    if (studentId != null && studentId.isNotEmpty) {
      ref.read(profileControllerProvider.notifier).fetchProfile(studentId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileControllerProvider);
    final analysisAsync = ref.watch(attendanceAnalysisProvider);
    final officialAsync = ref.watch(subjectWiseAttendanceProvider);
    final lastUpdated = ref.watch(lastUpdatedProvider);
    final target = ref.watch(attendanceTargetProvider);

    ref.listen(attendanceAnalysisProvider, (_, next) {
      next.whenOrNull(data: (_) {
        ref.read(lastUpdatedProvider.notifier).state = DateTime.now();
      });
    });

    final officialMap = officialAsync.whenOrNull(
      data: (list) {
        final map = <String, SubjectWiseAttendanceModel>{};
        for (final s in list) {
          map[s.subjectName] = s;
        }
        return map;
      },
    ) ?? <String, SubjectWiseAttendanceModel>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('PULSE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _ProfileSection(profileState: profileState),
            const SizedBox(height: 16),
            ...analysisAsync.when(
              loading: () => [const _LoadingIndicator()],
              error: (e, _) => [
                _ErrorCard(
                  message: e.toString().replaceFirst('Exception: ', ''),
                  onRetry: _onRefresh,
                ),
              ],
              data: (items) => _buildAttendanceContent(items, officialMap, lastUpdated, target),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAttendanceContent(
    List<AttendanceAnalysisItem> items,
    Map<String, SubjectWiseAttendanceModel> officialMap,
    DateTime? lastUpdated,
    double target,
  ) {
    if (items.isEmpty) {
      return [const _EmptyAttendance()];
    }

    int totalPresent = 0;
    int totalHours = 0;
    for (final item in items) {
      totalPresent += item.analysis.presentHours;
      totalHours += item.analysis.totalHours;
    }

    final overallPct = _computeOverallPercentage(totalPresent, totalHours);
    final safeBunks = AttendanceEngine.calculateSafeBunks(totalPresent, totalHours);
    final requiredClasses = AttendanceEngine.calculateRequiredClasses(totalPresent, totalHours);

    final lastUpdatedWidget = _LastUpdatedRow(lastUpdated: lastUpdated);

    return [
      _OverallCard(
        percentage: overallPct,
        present: totalPresent,
        total: totalHours,
        safeBunks: safeBunks,
        requiredClasses: requiredClasses,
        target: target,
      ),
      const SizedBox(height: 20),
      _SectionHeader(title: 'Subject-wise Attendance'),
      const SizedBox(height: 8),
      lastUpdatedWidget,
      ...items.map((item) {
        final officialModel = _findOfficialModel(item.subjectName, officialMap);
        return _SubjectCard(item: item, officialModel: officialModel, target: target);
      }),
    ];
  }

  static double _computeOverallPercentage(int present, int total) {
    if (total <= 0) return 0.0;
    return AttendanceUtils.roundPercentage(
      AttendanceUtils.clampPercentage(
        AttendanceUtils.safeDivide(present.toDouble(), total.toDouble()) * 100,
      ),
    );
  }

  static SubjectWiseAttendanceModel? _findOfficialModel(
    String name,
    Map<String, SubjectWiseAttendanceModel> officialMap,
  ) {
    if (officialMap.containsKey(name)) return officialMap[name];
    final normalized = _normalize(name);
    for (final entry in officialMap.entries) {
      if (_normalize(entry.key) == normalized) return entry.value;
    }
    return null;
  }
}

String _normalize(String s) {
  return s
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('( ', '(')
      .replaceAll(' )', ')')
      .replaceAll(' - ', '-')
      .trim();
}

class _ProfileSection extends StatelessWidget {
  final ProfileState profileState;

  const _ProfileSection({required this.profileState});

  @override
  Widget build(BuildContext context) {
    return switch (profileState.status) {
      ProfileStatus.loading => const _ProfileSkeleton(),
      ProfileStatus.error => _ProfileError(message: profileState.errorMessage ?? 'Could not load profile'),
      ProfileStatus.success => _ProfileCard(profile: profileState.profile!),
      ProfileStatus.idle => const SizedBox.shrink(),
    };
  }
}

class _ProfileCard extends StatelessWidget {
  final StudentProfile profile;

  const _ProfileCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = profile.name.isNotEmpty ? profile.name : 'Student';
    final registerNo = profile.registerNumber;
    final dept = profile.department;
    final semester = profile.academicTerm;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (registerNo.isNotEmpty)
                    Text(
                      registerNo,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (dept.isNotEmpty || semester.isNotEmpty)
                    Text(
                      [dept, semester].where((s) => s.isNotEmpty).join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 16, width: 160, color: cs.surfaceContainerHighest),
                  const SizedBox(height: 8),
                  Container(height: 12, width: 120, color: cs.surfaceContainerHighest),
                  const SizedBox(height: 6),
                  Container(height: 12, width: 180, color: cs.surfaceContainerHighest),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileError extends StatelessWidget {
  final String message;

  const _ProfileError({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.person_off, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverallCard extends StatelessWidget {
  final double percentage;
  final int present;
  final int total;
  final int safeBunks;
  final int requiredClasses;
  final double target;

  const _OverallCard({
    required this.percentage,
    required this.present,
    required this.total,
    required this.safeBunks,
    required this.requiredClasses,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, statusColor) = _computeStatus(percentage);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Overall Attendance', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: percentage / 100.0,
                      strokeWidth: 10,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(statusColor),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${percentage.toStringAsFixed(1)}%',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: statusColor),
                        ),
                        Text(
                          '$present / $total',
                          style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _StatChip(label: 'Safe Leaves', value: safeBunks.toString())),
                const SizedBox(width: 12),
                Expanded(child: _StatChip(label: 'Must Attend', value: requiredClasses.toString())),
              ],
            ),
          ],
        ),
      ),
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

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
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

class _SubjectCard extends StatelessWidget {
  final AttendanceAnalysisItem item;
  final SubjectWiseAttendanceModel? officialModel;
  final double target;

  const _SubjectCard({required this.item, this.officialModel, required this.target});

  @override
  Widget build(BuildContext context) {
    final a = item.analysis;
    final pct = officialModel?.finalPercentage ?? a.percentage;
    final present = officialModel?.effectivePresent ?? a.presentHours;
    final total = officialModel?.totalHours ?? a.totalHours;

    final safePct = AttendanceUtils.clampPercentage(pct);
    final safePresent = AttendanceUtils.clampIntToZero(present);
    final safeTotal = total > 0 ? total : 0;

    final safeBunks = AttendanceEngine.calculateSafeBunks(safePresent, safeTotal);
    final requiredClasses = AttendanceEngine.calculateRequiredClasses(safePresent, safeTotal);

    final (label, bg, fg) = _computeSubjectStatus(safePct);

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
                    item.subjectName,
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
            const SizedBox(height: 10),
            Row(
              children: [
                _SubjectStat(label: 'Attendance', value: '${safePct.toStringAsFixed(1)}%'),
                const SizedBox(width: 20),
                _SubjectStat(label: 'Present', value: '$safePresent'),
                const SizedBox(width: 20),
                _SubjectStat(label: 'Total', value: '$safeTotal'),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _SubjectStat(label: 'Safe Leaves', value: safeBunks.toString()),
                const SizedBox(width: 20),
                _SubjectStat(label: 'Must Attend', value: requiredClasses.toString()),
              ],
            ),
            if (officialModel != null && officialModel!.dutyLeave > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Duty Leave: ${officialModel!.dutyLeave}',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
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

class _SubjectStat extends StatelessWidget {
  final String label;
  final String value;

  const _SubjectStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ],
    );
  }
}

class _LastUpdatedRow extends StatelessWidget {
  final DateTime? lastUpdated;

  const _LastUpdatedRow({this.lastUpdated});

  @override
  Widget build(BuildContext context) {
    if (lastUpdated == null) return const SizedBox.shrink();
    final text = _formatLastUpdated(lastUpdated!);
    if (text.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
    );
  }

  static String _formatLastUpdated(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Updated just now';
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes} min ago';
    if (diff.inHours < 24) return 'Updated ${diff.inHours} hr ago';
    return 'Updated ${dt.day}/${dt.month}/${dt.year}';
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
              'Failed to load attendance',
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

class _EmptyAttendance extends StatelessWidget {
  const _EmptyAttendance();

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
              Icon(Icons.event_busy, size: 48, color: cs.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text(
                'No attendance data available',
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
