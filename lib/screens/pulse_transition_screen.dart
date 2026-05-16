import 'package:flutter/material.dart';

import 'main_shell_screen.dart';

class _CheckpointCurve extends Curve {
  const _CheckpointCurve();

  @override
  double transform(double t) {
    const phase1End = 0.50;
    const pauseEnd = 0.80;

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
  static const double _trackWidth = 260.0;
  static const Color _bgColor = Color(0xFF0B0E14);

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
      duration: const Duration(milliseconds: 4000),
    );

    _brandOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.04, 0.14, curve: Curves.easeOut),
    );

    _brandOffset = Tween<Offset>(
      begin: const Offset(0, 8),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.04, 0.14, curve: Curves.easeOut),
      ),
    );

    _taglineOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.14, 0.28, curve: Curves.easeOut),
    );

    _taglineOffset = Tween<Offset>(
      begin: const Offset(0, 8),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.14, 0.28, curve: Curves.easeOut),
      ),
    );

    _progress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.18, 0.95, curve: _CheckpointCurve()),
    );

    _exitOverlay = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.96, 1.0, curve: Curves.easeIn),
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

  Color _progressColor(double t) {
    if (t >= 0.95) return const Color(0xFF00897B);
    if (t >= 0.80) return const Color(0xFF43A047);
    if (t >= 0.75) return const Color(0xFFFB8C00);
    return const Color(0xFFE53935);
  }

  ({double scale, double glow, double hover}) _checkpointEffects(double progress) {
    const center = 0.75;
    const halfWidth = 0.10;

    final dist = (progress - center).abs() / halfWidth;
    if (dist >= 1.0) return (scale: 1.0, glow: 0.0, hover: 0.0);

    final bell = 1.0 - dist * dist;
    return (
      scale: 1.0 + 0.12 * bell,
      glow: 0.65 * bell,
      hover: -4.0 * bell,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: Stack(
        children: [
          SafeArea(
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _brandOpacity,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _brandOpacity.value,
                            child: Transform.translate(
                              offset: Offset(
                                0,
                                _brandOffset.value.dy,
                              ),
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          'PULSE',
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 14,
                            color: Colors.white.withValues(alpha: 0.92),
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
                              offset: Offset(
                                0,
                                _taglineOffset.value.dy,
                              ),
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          'Your attendance,\nunder your control.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            height: 1.5,
                            color: Colors.white.withValues(alpha: 0.50),
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 64,
                  child: Center(
                    child: SizedBox(
                      width: _trackWidth,
                      height: 40,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 8,
                            child: Container(
                              height: 2,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(1),
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFE53935),
                                    Color(0xFFFB8C00),
                                    Color(0xFF00897B),
                                  ],
                                  stops: [0.0, 0.75, 1.0],
                                ),
                              ),
                            ),
                          ),
                          _build75Node(),
                          Positioned(
                            left: 0,
                            top: 22,
                            child: Text(
                              '0',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.30),
                              ),
                            ),
                          ),
                          AnimatedBuilder(
                            animation: _progress,
                            builder: (context, child) {
                              final effects = _checkpointEffects(_progress.value);
                              return Positioned(
                                left: _trackWidth * 0.75 - 14,
                                top: 22,
                                child: Transform.translate(
                                  offset: Offset(0, effects.hover),
                                  child: Transform.scale(
                                    scale: effects.scale,
                                    child: SizedBox(
                                      width: 28,
                                      child: Text(
                                        '75',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white.withValues(
                                            alpha: 0.35 + 0.65 * effects.glow,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          Positioned(
                            right: 0,
                            top: 22,
                            child: Text(
                              '100',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.30),
                              ),
                            ),
                          ),
                          _buildGlowPoint(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
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

  Widget _build75Node() {
    return Positioned(
      left: _trackWidth * 0.75 - 3.5,
      top: 6.5,
      child: AnimatedBuilder(
        animation: _progress,
        builder: (context, child) {
          final progress = _progress.value;
          final crossed = progress >= 0.75;
          final effects = _checkpointEffects(progress);
          return Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFB8C00)
                  .withValues(alpha: crossed ? 1.0 : 0.25),
              border: Border.all(
                color: _bgColor,
                width: 1.5,
              ),
              boxShadow: crossed
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFB8C00)
                            .withValues(alpha: 0.20 + 0.25 * effects.glow),
                        blurRadius: 4 + 3 * effects.glow,
                        spreadRadius: 0.5 + 1.0 * effects.glow,
                      ),
                    ]
                  : null,
            ),
          );
        },
      ),
    );
  }

  Widget _buildGlowPoint() {
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, child) {
        final t = _progress.value;
        final color = _progressColor(t);
        final x = _trackWidth * t - 5;

        return Positioned(
          left: x,
          top: 3.5,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.20),
                  blurRadius: 5,
                  spreadRadius: 0.5,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
