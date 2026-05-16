import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/calculations/attendance_engine.dart';
import '../../../core/calculations/attendance_utils.dart';
import '../../profile/controllers/profile_controller.dart';
import '../../profile/models/student_profile.dart';
import '../../../models/api/subject_wise_attendance_model.dart';
import '../../../providers/attendance_analysis_provider.dart';
import '../../../providers/attendance_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/subject_wise_attendance_provider.dart';
import '../../../features/settings/providers/settings_providers.dart';
import '../../dashboard/providers/dashboard_providers.dart';

class DashboardTab extends ConsumerStatefulWidget {
  const DashboardTab({super.key});

  @override
  ConsumerState<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends ConsumerState<DashboardTab> {
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
    final trigger = ref.watch(dashboardTabTriggerProvider);

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
      body: Stack(
        children: [
          RefreshIndicator(
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
                  data: (items) => _buildAttendanceContent(items, officialMap, lastUpdated, target, trigger),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 24,
            right: 20,
            child: _FloatingRefreshButton(onRefresh: _onRefresh),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAttendanceContent(
    List<AttendanceAnalysisItem> items,
    Map<String, SubjectWiseAttendanceModel> officialMap,
    DateTime? lastUpdated,
    double target,
    int trigger,
  ) {
    if (items.isEmpty) {
      return [const _EmptyAttendance()];
    }

    int totalPresent = 0;
    int totalHours = 0;
    if (officialMap.isNotEmpty) {
      for (final s in officialMap.values) {
        totalPresent += s.effectivePresent;
        totalHours += s.totalHours;
      }
    } else {
      for (final item in items) {
        totalPresent += item.analysis.presentHours;
        totalHours += item.analysis.totalHours;
      }
    }

    final overallPct = _computeOverallPercentage(totalPresent, totalHours);
    final safeBunks = AttendanceEngine.calculateSafeBunks(totalPresent, totalHours);
    final requiredClasses = AttendanceEngine.calculateRequiredClasses(totalPresent, totalHours);

    return [
      _OverallCard(
        percentage: overallPct,
        present: totalPresent,
        total: totalHours,
        safeBunks: safeBunks,
        requiredClasses: requiredClasses,
        target: target,
        trigger: trigger,
      ),
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
    final name = profile.name;
    final batchName = profile.batchName;
    final currentSem = profile.currentSem;
    final imageUrl = profile.imageUrl;

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
              backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
              child: imageUrl.isEmpty
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (name.isNotEmpty)
                    Text(
                      name,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (batchName.isNotEmpty)
                    Text(
                      batchName,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (currentSem.isNotEmpty)
                    Text(
                      currentSem,
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
  final int trigger;

  const _OverallCard({
    required this.percentage,
    required this.present,
    required this.total,
    required this.safeBunks,
    required this.requiredClasses,
    required this.target,
    required this.trigger,
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
              child: _AnimatedGauge(
                percentage: percentage,
                present: present,
                total: total,
                statusColor: statusColor,
                trigger: trigger,
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

class _AnimatedGauge extends StatefulWidget {
  final double percentage;
  final int present;
  final int total;
  final Color statusColor;
  final int trigger;

  const _AnimatedGauge({
    required this.percentage,
    required this.present,
    required this.total,
    required this.statusColor,
    required this.trigger,
  });

  @override
  State<_AnimatedGauge> createState() => _AnimatedGaugeState();
}

class _AnimatedGaugeState extends State<_AnimatedGauge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _gaugeAnimation;
  double _finalValue = 0;
  int _lastTrigger = 0;

  @override
  void initState() {
    super.initState();
    _finalValue = widget.percentage / 100.0;
    _lastTrigger = widget.trigger;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _gaugeAnimation = _controller.drive(
      CurveTween(curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(_AnimatedGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != _lastTrigger) {
      _lastTrigger = widget.trigger;
      _finalValue = widget.percentage / 100.0;
      _controller
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _gaugeAnimation,
              builder: (context, child) {
                return CircularProgressIndicator(
                  value: _gaugeAnimation.value * _finalValue,
                  strokeWidth: 6,
                  backgroundColor: cs.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(widget.statusColor),
                );
              },
            ),
          ),
          SizedBox(
            width: 140,
            height: 140,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.translate(
                    offset: const Offset(0, -8),
                    child: AnimatedBuilder(
                      animation: _gaugeAnimation,
                      builder: (context, child) {
                        final displayValue = _gaugeAnimation.value * _finalValue * 100;
                        return Text(
                          '${displayValue.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: widget.statusColor,
                          ),
                          textAlign: TextAlign.center,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.present} / ${widget.total}',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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

class _FloatingRefreshButton extends StatefulWidget {
  final Future<void> Function() onRefresh;

  const _FloatingRefreshButton({required this.onRefresh});

  @override
  State<_FloatingRefreshButton> createState() => _FloatingRefreshButtonState();
}

class _FloatingRefreshButtonState extends State<_FloatingRefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;
  bool _isRefreshing = false;
  bool _showTooltip = true;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showTooltip = false);
    });
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      _showTooltip = false;
    });
    _rotationController.repeat();
    await widget.onRefresh();
    if (mounted) {
      _rotationController.stop();
      _rotationController.reset();
      setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_showTooltip)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Refresh',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
          ),
        FloatingActionButton.small(
          onPressed: _onTap,
          elevation: 3,
          backgroundColor: cs.primaryContainer,
          foregroundColor: cs.onPrimaryContainer,
          child: AnimatedBuilder(
            animation: _rotationController,
            builder: (context, child) {
              return Transform.rotate(
                angle: _rotationController.value * 2 * pi,
                child: child,
              );
            },
            child: const Icon(Icons.refresh, size: 20),
          ),
        ),
      ],
    );
  }
}
