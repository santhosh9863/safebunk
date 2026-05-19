import 'dart:math' show pi, cos, sin;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/calculations/attendance_engine.dart';
import '../../../core/calculations/attendance_utils.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../core/notifications/notification_scheduler.dart';
import '../../profile/controllers/profile_controller.dart';
import '../../profile/models/student_profile.dart';
import '../../../models/api/subject_wise_attendance_model.dart';
import '../../../providers/attendance_analysis_provider.dart';
import '../../../providers/attendance_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/subject_wise_attendance_provider.dart';
import '../../../services/analytics_service.dart';
import '../../../features/settings/providers/settings_providers.dart';
import '../../dashboard/providers/dashboard_providers.dart';
import '../../dashboard/widgets/attendance_qa_card.dart';
import '../../dashboard/widgets/attendance_simulator_card.dart';
import '../../dashboard/widgets/attendance_simulation_helper.dart';

class DashboardTabV2 extends ConsumerStatefulWidget {
  const DashboardTabV2({super.key});

  @override
  ConsumerState<DashboardTabV2> createState() => _DashboardTabV2State();
}

class _ShimmerWidget extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const _ShimmerWidget({
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<_ShimmerWidget> createState() => _ShimmerWidgetState();
}

class _ShimmerWidgetState extends State<_ShimmerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(begin: -1, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              colors: [
                cs.surfaceContainerHighest.withValues(alpha: 0.4),
                cs.surfaceContainerHighest.withValues(alpha: 0.7),
                cs.surfaceContainerHighest.withValues(alpha: 0.4),
              ],
              stops: [
                (_animation.value - 1).clamp(0.0, 1.0),
                _animation.value.clamp(0.0, 1.0),
                (_animation.value + 1).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DashboardTabV2State extends ConsumerState<DashboardTabV2> {
  bool _profileInitialized = false;
  bool _isRefreshing = false;

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

  void _evaluateNotifications(List<AttendanceAnalysisItem> items) {
    final scheduler = ref.read(notificationSchedulerProvider);
    if (scheduler == null) return;

    int totalPresent = 0;
    int totalHours = 0;
    for (final item in items) {
      totalPresent += item.analysis.presentHours;
      totalHours += item.analysis.totalHours;
    }

    final overallPct = _computeOverallPercentage(totalPresent, totalHours);
    final safeBunks = AttendanceEngine.calculateSafeBunks(totalPresent, totalHours);
    final target = ref.read(attendanceTargetProvider);
    final alertsEnabled = ref.read(attendanceAlertsProvider);
    final lowWarningEnabled = ref.read(lowAttendanceWarningProvider);
    final dailyReminderEnabled = ref.read(dailyReminderProvider);
    final weeklySummaryEnabled = ref.read(weeklySummaryProvider);

    scheduler.evaluate(
      overallPercentage: overallPct,
      safeBunks: safeBunks,
      attendanceTarget: target,
      now: DateTime.now(),
      settings: NotificationSettings(
        notificationsEnabled: alertsEnabled,
        lowAttendanceEnabled: lowWarningEnabled,
        dailyReminderEnabled: dailyReminderEnabled,
        weeklySummaryEnabled: weeklySummaryEnabled,
      ),
    );
  }

  Future<void> _onRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      ref.read(cacheManagerProvider).clearAll();
      ref.invalidate(subjectAttendanceProvider);
      ref.invalidate(subjectWiseAttendanceProvider);
      final sessionManager = ref.read(sessionManagerProvider);
      final studentId = await sessionManager.getStudentId();
      if (studentId != null && studentId.isNotEmpty) {
        await ref.read(profileControllerProvider.notifier).fetchProfile(studentId);
      }
      AnalyticsService.logAttendanceSync();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Sync failed'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 80,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
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
      next.whenOrNull(data: (items) {
        ref.read(lastUpdatedProvider.notifier).state = DateTime.now();
        _evaluateNotifications(items);
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
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: _onRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _BrandHeader(onLogout: () => ref.read(authProvider.notifier).logout()),
                  const SizedBox(height: 8),
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

    final subjectEntries = items.map((item) => SubjectEntry(
      displayName: AttendanceUtils.cleanSubjectName(item.subjectName),
      presentHours: item.analysis.presentHours,
      totalHours: item.analysis.totalHours,
    )).toList();

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
      const SizedBox(height: 12),
      if (lastUpdated != null) ...[
        _SyncStatusRow(
          lastUpdated: lastUpdated,
          isRefreshing: _isRefreshing,
          onRefresh: _onRefresh,
        ),
        const SizedBox(height: 8),
      ],
      AttendanceQACard(
        totalPresent: totalPresent,
        totalHours: totalHours,
        target: target,
      ),
      const SizedBox(height: 16),
      AttendanceSimulatorCard(
        subjects: subjectEntries,
        totalPresent: totalPresent,
        totalHours: totalHours,
        target: target,
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
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const _ShimmerWidget(width: 56, height: 56, borderRadius: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _ShimmerWidget(width: 160, height: 16),
                  const SizedBox(height: 8),
                  const _ShimmerWidget(width: 120, height: 12),
                  const SizedBox(height: 6),
                  const _ShimmerWidget(width: 180, height: 12),
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

class _BrandHeader extends StatelessWidget {
  final VoidCallback onLogout;

  const _BrandHeader({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PULSE',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Attendance Intelligence',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.70),
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.logout, size: 20),
            onPressed: onLogout,
            tooltip: 'Logout',
            style: IconButton.styleFrom(
              foregroundColor: cs.onSurfaceVariant,
            ),
          ),
        ],
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
                Text(
                  'Overall Attendance',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: _InstrumentGauge(
                percentage: percentage,
                present: present,
                total: total,
                statusColor: statusColor,
                trigger: trigger,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatChip(
                    label: 'Safe Leaves',
                    value: safeBunks.toString(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatChip(
                    label: 'Must Attend',
                    value: requiredClasses.toString(),
                  ),
                ),
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

class _InstrumentGauge extends StatefulWidget {
  final double percentage;
  final int present;
  final int total;
  final Color statusColor;
  final int trigger;

  const _InstrumentGauge({
    required this.percentage,
    required this.present,
    required this.total,
    required this.statusColor,
    required this.trigger,
  });

  @override
  State<_InstrumentGauge> createState() => _InstrumentGaugeState();
}

class _InstrumentGaugeState extends State<_InstrumentGauge>
    with SingleTickerProviderStateMixin {
  static const _gaugeWidth = 220.0;
  static const _gaugeHeight = 135.0;

  static const _gradientColors = [
    Color(0xFF1B2D4A),
    Color(0xFF4A7FB5),
    Color(0xFF6BB5B5),
  ];

  late final AnimationController _controller;
  late final Animation<double> _animation;
  double _finalValue = 0;
  int _lastTrigger = 0;

  @override
  void initState() {
    super.initState();
    _finalValue = widget.percentage.clamp(0, 100) / 100.0;
    _lastTrigger = widget.trigger;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = _controller.drive(
      CurveTween(curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(_InstrumentGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != _lastTrigger) {
      _lastTrigger = widget.trigger;
      _finalValue = widget.percentage.clamp(0, 100) / 100.0;
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
      width: _gaugeWidth,
      height: _gaugeHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return CustomPaint(
                painter: _InstrumentPainter(
                  progress: _animation.value * _finalValue,
                  trackColor: cs.surfaceContainerHighest,
                  gradientColors: _gradientColors,
                ),
                size: const Size(_gaugeWidth, _gaugeHeight),
              );
            },
          ),
          Positioned(
            top: 66,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) {
                    final displayValue = _animation.value * _finalValue * 100;
                    return Text(
                      '${displayValue.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                        color: cs.primary,
                      ),
                      textAlign: TextAlign.center,
                    );
                  },
                ),
                const SizedBox(height: 3),
                Text(
                  '${widget.present} / ${widget.total} classes',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InstrumentPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final List<Color> gradientColors;

  const _InstrumentPainter({
    required this.progress,
    required this.trackColor,
    required this.gradientColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 9.0;
    final halfStroke = strokeWidth / 2;
    final center = Offset(size.width / 2, size.width / 2);
    final radius = size.width / 2 - halfStroke - 6;

    final arcRect = Rect.fromCircle(center: center, radius: radius);

    final bgPaint = Paint()
      ..color = trackColor.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(arcRect, pi, pi, false, bgPaint);

    if (progress > 0) {
      final sweepAngle = pi * progress;
      final progressPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: gradientColors,
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

      canvas.drawArc(arcRect, pi, sweepAngle, false, progressPaint);
    }

    final tickPaint = Paint()
      ..color = trackColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    const tickCount = 6;
    for (int i = 1; i < tickCount; i++) {
      final angle = pi + (pi / tickCount) * i;
      final inner = Offset(
        center.dx + (radius - 5) * cos(angle),
        center.dy + (radius - 5) * sin(angle),
      );
      final outer = Offset(
        center.dx + (radius + 3) * cos(angle),
        center.dy + (radius + 3) * sin(angle),
      );
      canvas.drawLine(inner, outer, tickPaint);
    }

    if (progress > 0) {
      final endpointAngle = pi + pi * progress;
      final endpointPos = Offset(
        center.dx + radius * cos(endpointAngle),
        center.dy + radius * sin(endpointAngle),
      );

      final markerPaint = Paint()
        ..color = const Color(0xFF6BB5B5)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(endpointPos, 4.5, markerPaint);
    }
  }

  @override
  bool shouldRepaint(_InstrumentPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor;
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
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                const _ShimmerWidget(width: 140, height: 18),
                const _ShimmerWidget(width: 60, height: 22, borderRadius: 11),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  const _ShimmerWidget(width: 120, height: 48),
                  const SizedBox(height: 8),
                  const _ShimmerWidget(width: 100, height: 14),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Column(
                      children: [
                        _ShimmerWidget(width: 30, height: 18),
                        SizedBox(height: 4),
                        _ShimmerWidget(width: 60, height: 11),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Column(
                      children: [
                        _ShimmerWidget(width: 30, height: 18),
                        SizedBox(height: 4),
                        _ShimmerWidget(width: 60, height: 11),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
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
    final cs = Theme.of(context).colorScheme;

    final displayMessage = _humanizeError(message);

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
              'Unable to load attendance',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              displayMessage,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  static String _humanizeError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('connection') || lower.contains('timeout') || lower.contains('socket')) {
      return 'Unable to reach your college server. Check your connection and try again.';
    }
    if (lower.contains('unauthorized') || lower.contains('session') || lower.contains('expired')) {
      return 'Your session may have expired. Try refreshing or logging in again.';
    }
    if (lower.contains('not found') || lower.contains('404')) {
      return 'Attendance data is temporarily unavailable.';
    }
    if (lower.contains('server') || lower.contains('500') || lower.contains('502') || lower.contains('503')) {
      return 'The college server encountered an issue. Please try again later.';
    }
    return 'Unable to refresh attendance right now.';
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
                'No attendance data yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Pull down to sync your latest records.',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncStatusRow extends StatefulWidget {
  final DateTime? lastUpdated;
  final bool isRefreshing;
  final Future<void> Function() onRefresh;

  const _SyncStatusRow({
    required this.lastUpdated,
    required this.isRefreshing,
    required this.onRefresh,
  });

  @override
  State<_SyncStatusRow> createState() => _SyncStatusRowState();
}

class _SyncStatusRowState extends State<_SyncStatusRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (widget.isRefreshing) _spinController.repeat();
  }

  @override
  void didUpdateWidget(_SyncStatusRow old) {
    super.didUpdateWidget(old);
    if (widget.isRefreshing && !old.isRefreshing) {
      _spinController.repeat();
    } else if (!widget.isRefreshing && old.isRefreshing) {
      _spinController.stop();
      _spinController.reset();
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lastUpdated == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final text = _format(widget.lastUpdated!);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          Icon(
            Icons.history,
            size: 12,
            color: cs.onSurfaceVariant.withValues(alpha: 0.55),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant.withValues(alpha: 0.65),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: widget.isRefreshing ? null : () => widget.onRefresh(),
            child: AnimatedBuilder(
              animation: _spinController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _spinController.value * 2 * pi,
                  child: child,
                );
              },
              child: Icon(
                Icons.refresh,
                size: 16,
                color: widget.isRefreshing
                    ? cs.primary.withValues(alpha: 0.4)
                    : cs.primary.withValues(alpha: 0.65),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _format(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Synced just now';
    if (diff.inMinutes < 60) return 'Synced ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Synced ${diff.inHours}h ago';
    return 'Synced ${dt.day}/${dt.month}';
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
                'Sync attendance',
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
