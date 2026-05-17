import 'package:flutter/material.dart';

import 'main_shell_screen.dart';

class _CheckpointCurve extends Curve {
  const _CheckpointCurve();

  @override
  double transform(double t) {
    const phase1End = 0.70;
    const pauseEnd = 0.82;

    if (t < phase1End) {
      final local = t / phase1End;
      return 0.75 * _easeInOutCubic(local);
    } else if (t < pauseEnd) {
      return 0.75;
    } else {
      final local = (t - pauseEnd) / (1.0 - pauseEnd);
      return 0.75 + 0.25 * _easeInOutCubic(local);
    }
  }

  static double _easeInOutCubic(double t) {
    return t < 0.5
        ? 4 * t * t * t
        : 1 - 4 * (1 - t) * (1 - t) * (1 - t);
  }
}

class PulseTransitionScreen extends StatefulWidget {
  const PulseTransitionScreen({super.key});

  @override
  State<PulseTransitionScreen> createState() => _PulseTransitionScreenState();
}

class _PulseTransitionScreenState extends State<PulseTransitionScreen>
    with SingleTickerProviderStateMixin {
  static const Color _bgColor = Color(0xFFF8FAFC);
  static const double _trackWidth = 200.0;

  late final AnimationController _controller;
  late final Animation<double> _brandOpacity;
  late final Animation<Offset> _brandOffset;
  late final Animation<double> _taglineOpacity;
  late final Animation<Offset> _taglineOffset;
  late final Animation<double> _progress;
  late final Animation<double> _exitOverlay;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    _brandOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.04, 0.16, curve: Curves.easeOut),
    );

    _brandOffset = Tween<Offset>(
      begin: const Offset(0, 8),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.04, 0.16, curve: Curves.easeOut),
      ),
    );

    _taglineOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.16, 0.30, curve: Curves.easeOut),
    );

    _taglineOffset = Tween<Offset>(
      begin: const Offset(0, 8),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.16, 0.30, curve: Curves.easeOut),
      ),
    );

    _progress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.28, 0.93, curve: _CheckpointCurve()),
    );

    _exitOverlay = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.95, 1.0, curve: Curves.easeIn),
    );

    _controller.forward().then((_) {
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          PageRouteBuilder(
            pageBuilder: (_, _, _) => const MainShellScreen(),
            transitionsBuilder: (_, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 280),
          ),
          (route) => false,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ({double scale, double glow, bool active}) _checkpointEffects(double progress) {
    const center = 0.75;
    const halfWidth = 0.08;

    final dist = (progress - center).abs() / halfWidth;
    if (dist >= 1.0) return (scale: 1.0, glow: 0.0, active: progress >= center);

    final bell = 1.0 - dist * dist;
    return (
      scale: 1.0 + 0.08 * bell,
      glow: 0.50 * bell,
      active: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _brandOpacity,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _brandOpacity.value,
                        child: Transform.translate(
                          offset: _brandOffset.value,
                          child: child,
                        ),
                      );
                    },
                    child: const Text(
                      'PULSE',
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 14,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  AnimatedBuilder(
                    animation: _taglineOpacity,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _taglineOpacity.value,
                        child: Transform.translate(
                          offset: _taglineOffset.value,
                          child: child,
                        ),
                      );
                    },
                    child: const Text(
                      'Your attendance,\nunder your control.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        height: 1.5,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 44),
                  SizedBox(
                    width: _trackWidth,
                    height: 44,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 8,
                          child: SizedBox(
                            height: 3,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(1.5),
                              child: AnimatedBuilder(
                                animation: _progress,
                                builder: (context, child) {
                                  return CustomPaint(
                                    painter: _ProgressBarPainter(
                                      progress: _progress.value,
                                    ),
                                    size: const Size(200, 3),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: _trackWidth * 0.75 - 5,
                          top: 5.5,
                          child: AnimatedBuilder(
                            animation: _progress,
                            builder: (context, child) {
                              final effects = _checkpointEffects(_progress.value);
                              return Transform.scale(
                                scale: effects.scale,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF3B82F6)
                                        .withValues(alpha: effects.active ? 1.0 : 0.25),
                                    border: Border.all(
                                      color: _bgColor,
                                      width: 2,
                                    ),
                                    boxShadow: effects.active
                                        ? [
                                            BoxShadow(
                                              color: const Color(0xFF3B82F6)
                                                  .withValues(alpha: 0.15 + 0.25 * effects.glow),
                                              blurRadius: 4 + 2 * effects.glow,
                                              spreadRadius: 0.5 + effects.glow,
                                            ),
                                          ]
                                        : null,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Positioned(
                          left: _trackWidth * 0.75 - 10,
                          top: 24,
                          child: AnimatedBuilder(
                            animation: _progress,
                            builder: (context, child) {
                              final effects = _checkpointEffects(_progress.value);
                              return SizedBox(
                                width: 20,
                                child: Text(
                                  '75',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF475569).withValues(
                                      alpha: 0.40 + 0.60 * effects.glow,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Loading dashboard...',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: _exitOverlay,
                child: Container(color: _bgColor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  final double progress;

  _ProgressBarPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeCap = StrokeCap.round;

    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(1.5),
    );
    canvas.drawRRect(trackRect, trackPaint);

    if (progress <= 0) return;

    final fillWidth = size.width * progress.clamp(0.0, 1.0);

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFF60A5FA),
          Color(0xFF2563EB),
        ],
        stops: [0.0, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, fillWidth, size.height));

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, fillWidth, size.height),
        const Radius.circular(1.5),
      ),
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(_ProgressBarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
