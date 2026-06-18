import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../services/metronome.dart';

/// A small classic metronome whose arm swings one side per beat, in sync with
/// the click. The downbeat flashes accent-colored. Driven by [Metronome]'s
/// beat stream so the visual stays locked to the audio.
class MetronomeVisual extends StatefulWidget {
  final Metronome metronome;
  const MetronomeVisual({super.key, required this.metronome});

  @override
  State<MetronomeVisual> createState() => _MetronomeVisualState();
}

class _MetronomeVisualState extends State<MetronomeVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  StreamSubscription<int>? _sub;

  double _from = -1; // previous arm extreme (-1 left, +1 right)
  double _to = -1; // target arm extreme
  int _flashBeat = -1; // which beat we're flashing for (0 = accent)

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addListener(() => setState(() {}));
    _sub = widget.metronome.beatStream.listen(_onBeat);
  }

  void _onBeat(int beat) {
    final bpm = widget.metronome.bpm;
    _from = _to;
    _to = -_to; // swing to the opposite side
    _flashBeat = beat;
    _controller
      ..duration = Duration(microseconds: (60000000 / bpm).round())
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = widget.metronome.running;
    final t = Curves.easeInOut.transform(_controller.value);
    // When stopped, rest the arm upright at center.
    final swing = running ? (lerpDouble(_from, _to, t) ?? 0) : 0.0;
    // Flash fades over the beat; brighter on the downbeat.
    final flashStrength = running ? (1 - _controller.value) : 0.0;

    return SizedBox(
      width: 130,
      height: 170,
      child: CustomPaint(
        painter: _MetronomePainter(
          swing: swing,
          flashStrength: flashStrength,
          isAccent: _flashBeat == 0,
          accentColor: Theme.of(context).colorScheme.primary,
          bodyColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          armColor: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _MetronomePainter extends CustomPainter {
  final double swing; // -1..1
  final double flashStrength; // 0..1
  final bool isAccent;
  final Color accentColor;
  final Color bodyColor;
  final Color armColor;

  static const double maxAngle = 0.42; // radians at full swing

  _MetronomePainter({
    required this.swing,
    required this.flashStrength,
    required this.isAccent,
    required this.accentColor,
    required this.bodyColor,
    required this.armColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Trapezoid metronome body.
    final body = Path()
      ..moveTo(w * 0.30, h * 0.12)
      ..lineTo(w * 0.70, h * 0.12)
      ..lineTo(w * 0.86, h * 0.95)
      ..lineTo(w * 0.14, h * 0.95)
      ..close();
    canvas.drawPath(body, Paint()..color = bodyColor);
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = armColor.withValues(alpha: 0.35),
    );

    // Pivot near the bottom-center of the body.
    final pivot = Offset(w * 0.5, h * 0.82);
    final angle = swing * maxAngle;
    final armLen = h * 0.62;
    final tip = Offset(
      pivot.dx + math.sin(angle) * armLen,
      pivot.dy - math.cos(angle) * armLen,
    );

    // Arm.
    canvas.drawLine(
      pivot,
      tip,
      Paint()
        ..color = armColor
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );

    // Sliding weight on the arm.
    final weightPos = Offset(
      pivot.dx + math.sin(angle) * armLen * 0.62,
      pivot.dy - math.cos(angle) * armLen * 0.62,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: weightPos, width: 16, height: 11),
        const Radius.circular(2),
      ),
      Paint()..color = armColor,
    );

    // Pivot cap.
    canvas.drawCircle(pivot, 5, Paint()..color = accentColor);

    // Beat flash: a glowing dot at the top, brighter/larger on the downbeat.
    if (flashStrength > 0) {
      final c = isAccent ? accentColor : armColor;
      final radius = (isAccent ? 11.0 : 7.0) * (0.5 + flashStrength * 0.5);
      canvas.drawCircle(
        Offset(w * 0.5, h * 0.06),
        radius,
        Paint()
          ..color = c.withValues(alpha: flashStrength * (isAccent ? 0.95 : 0.6))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MetronomePainter old) =>
      old.swing != swing ||
      old.flashStrength != flashStrength ||
      old.isAccent != isAccent;
}

/// A row of dots, one per beat in the bar, highlighting the current beat.
class BeatIndicator extends StatelessWidget {
  final Metronome metronome;
  const BeatIndicator({super.key, required this.metronome});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(metronome.beatsPerBar, (i) {
        final active = metronome.running && i == metronome.currentBeat;
        final isDownbeat = i == 0;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 16 : 12,
          height: active ? 16 : 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? (isDownbeat ? cs.primary : cs.secondary)
                : cs.onSurface.withValues(alpha: 0.18),
          ),
        );
      }),
    );
  }
}
