import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'main_shell_screen.dart';

// ── Smooth continuous progress curve ──

class _RefinedCurve extends Curve {
  const _RefinedCurve();

  @override
  double transform(double t) {
    const p1 = 0.780; // 0 → 75 (smooth easeOutCubic)
    const p2 = 0.925; // hold at 75 (~500ms)

    if (t < p1) {
      final local = t / p1;
      return 0.75 * _easeOutCubic(local);
    } else if (t < p2) {
      return 0.75;
    } else {
      final local = (t - p2) / (1.0 - p2);
      return lerpDouble(0.75, 1.0, _easeOutQuad(local))!;
    }
  }

  static double _easeOutCubic(double t) {
    final v = 1.0 - t;
    return 1.0 - v * v * v;
  }

  static double _easeOutQuad(double t) => t * (2.0 - t);
}

// ── Loading message rotation ──

class _MessageSequence {
  static const List<String> messages = [
    'Preparing your attendance insights',
    'Syncing attendance intelligence',
    'Analyzing attendance patterns',
    'Building your dashboard',
  ];

  final double controllerValue;

  _MessageSequence(this.controllerValue);

  String get current {
    final idx = (controllerValue * (messages.length - 1)).round().clamp(0, messages.length - 1);
    return messages[idx];
  }
}

// ── Main screen ──

class PulseTransitionScreen extends StatefulWidget {
  const PulseTransitionScreen({super.key});

  @override
  State<PulseTransitionScreen> createState() => _PulseTransitionScreenState();
}

class _PulseTransitionScreenState extends State<PulseTransitionScreen>
    with TickerProviderStateMixin {
  static const Color _bgColor = Color(0xFFF8FAFC);
  static const double _trackLength = 184.0;

  late final AnimationController _controller;
  late final Animation<double> _brandOpacity;
  late final Animation<Offset> _brandOffset;
  late final Animation<double> _taglineOpacity;
  late final Animation<Offset> _taglineOffset;
  late final Animation<double> _progress;
  late final Animation<double> _exitOverlay;

  late final AnimationController _breathController;
  late final Animation<double> _breath;

  String _currentMessage = _MessageSequence.messages[0];
  double _messageOpacity = 0.0;

  @override
  void initState() {
    super.initState();

    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    _breath = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _breathController, curve: Curves.easeInOut),
    );
    _breathController.repeat(reverse: true);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
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
      curve: const Interval(0.28, 0.92, curve: _RefinedCurve()),
    );

    _exitOverlay = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.95, 1.0, curve: Curves.easeIn),
    );

    _messageOpacity = 0.0;

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

    _controller.addListener(_updateMessage);
  }

  void _updateMessage() {
    final cv = _controller.value;
    final newMsg = _MessageSequence(cv).current;

    final rawIdx = cv * (_MessageSequence.messages.length - 1);
    final frac = rawIdx - rawIdx.floor().toDouble();
    final targetOpacity = frac > 0.5 ? 1.0 - (frac - 0.5) * 2.0 : frac * 2.0;
    final smoothed = targetOpacity.clamp(0.0, 1.0);

    if (newMsg != _currentMessage) {
      setState(() {
        _currentMessage = newMsg;
      });
    }
    setState(() {
      _messageOpacity = smoothed;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_updateMessage);
    _controller.dispose();
    _breathController.dispose();
    super.dispose();
  }

  // ── Glow pulse during 75% settled phase ──

  double _glowPulse(double raw) {
    const holdStart = 0.780;
    const holdEnd = 0.925;
    if (raw < holdStart || raw > holdEnd) return 0.0;
    final local = (raw - holdStart) / (holdEnd - holdStart);
    if (local < 0.5) {
      return (local / 0.5) * 0.20;
    } else {
      final decay = 1.0 - (local - 0.5) / 0.5;
      return decay * 0.20;
    }
  }

  double _bloomPulse(double raw) {
    const bloomStart = 0.88;
    const bloomEnd = 0.94;
    if (raw < bloomStart || raw > bloomEnd) return 0.0;
    final local = (raw - bloomStart) / (bloomEnd - bloomStart);
    return math.sin(local * math.pi) * 0.15;
  }

  @override
  Widget build(BuildContext context) {
    final breathValue = _breath.value;
    final breathScale = 1.0 + breathValue * 0.02;
    final breathOpacity = 0.96 + breathValue * 0.04;

    return Scaffold(
      backgroundColor: _bgColor,
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Brand with breathing ──
                  AnimatedBuilder(
                    animation: Listenable.merge([_brandOpacity, _breathController]),
                    builder: (context, child) {
                      return Opacity(
                        opacity: _brandOpacity.value * breathOpacity,
                        child: Transform.translate(
                          offset: _brandOffset.value,
                          child: Transform.scale(
                            scale: breathScale,
                            child: child,
                          ),
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
                  // ── Tagline ──
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
                  const SizedBox(height: 48),
                  // ── Progress Track ──
                  SizedBox(
                    width: _trackLength,
                    height: 36,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Track + Fill
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 10,
                          child: SizedBox(
                            height: 2,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(1),
                              child: AnimatedBuilder(
                                animation: _progress,
                                builder: (context, child) {
                                  final p = _progress.value;
                                  final cv = _controller.value;
                                  final gp = _glowPulse(cv);
                                  final bp = _bloomPulse(cv);
                                  final shimmer = (math.sin(cv * math.pi * 5) * 0.5 + 0.5);
                                  return CustomPaint(
                                    painter: _ProgressBarPainter(
                                      progress: p,
                                      glowIntensity: gp + bp,
                                      shimmerPhase: shimmer,
                                    ),
                                    size: const Size(_trackLength, 2),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        // Percentage
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: AnimatedBuilder(
                            animation: _progress,
                            builder: (context, child) {
                              final p = _progress.value;
                              final clampedP = p.clamp(0.0, 1.0);
                              final pct = (clampedP * 100).round().clamp(0, 100);
                              final cv = _controller.value;
                              final gp = _glowPulse(cv);
                              final bp = _bloomPulse(cv);
                              final enhanced = (gp + bp).clamp(0.0, 1.0);
                              final alpha = (0.35 + 0.65 * clampedP).clamp(0.0, 1.0);
                              return Text(
                                '$pct%',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF1E293B).withValues(alpha: alpha + enhanced * 0.65),
                                  letterSpacing: 1.2,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // ── Loading messages ──
                  SizedBox(
                    height: 18,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _taglineOpacity.value * 0.55 * _messageOpacity,
                          child: child,
                        );
                      },
                      child: Text(
                        _currentMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF64748B),
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Exit overlay ──
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

// ── Progress bar painter with glow and shimmer ──

class _ProgressBarPainter extends CustomPainter {
  final double progress;
  final double glowIntensity;
  final double shimmerPhase;

  _ProgressBarPainter({
    required this.progress,
    required this.glowIntensity,
    required this.shimmerPhase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fillWidth = size.width * progress.clamp(0.0, 1.0);
    const corner = Radius.circular(1);

    // Track
    final trackPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeCap = StrokeCap.round;
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      corner,
    );
    canvas.drawRRect(trackRect, trackPaint);

    if (progress <= 0) return;

    // Ambient glow behind fill head
    if (glowIntensity > 0.01) {
      final glow = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF3B82F6).withValues(alpha: glowIntensity * 0.35),
            const Color(0xFF3B82F6).withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(
          fillWidth - 24,
          -6,
          48,
          size.height + 12,
        ));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, -2, fillWidth + 8, size.height + 4),
          const Radius.circular(3),
        ),
        glow,
      );
    }

    // Fill gradient
    final fillPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFF60A5FA),
          Color(0xFF3B82F6),
        ],
      ).createShader(Rect.fromLTWH(0, 0, fillWidth, size.height));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, fillWidth, size.height),
        corner,
      ),
      fillPaint,
    );

    // Subtle shimmer sweep (near-transparent white band)
    if (fillWidth > 10) {
      final shimmerX = shimmerPhase * fillWidth;
      final shimmerPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0x00FFFFFF),
            const Color(0x30FFFFFF),
            const Color(0x00FFFFFF),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromLTWH(
          shimmerX - 12,
          0,
          24,
          size.height,
        ));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, fillWidth, size.height),
          corner,
        ),
        shimmerPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ProgressBarPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.glowIntensity != glowIntensity ||
      oldDelegate.shimmerPhase != shimmerPhase;
}
