import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings.dart';
import '../services/tuner.dart';
import '../ui/studio.dart';
import '../widgets/coach_marks.dart';

class TunerScreen extends StatefulWidget {
  const TunerScreen({super.key});

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> {
  // Mic start/stop is driven by RootShell when this tab is shown/hidden, so it
  // doesn't run while other tabs are active.

  @override
  Widget build(BuildContext context) {
    final t = context.watch<Tuner>();
    final settings = context.watch<AppSettings>();
    // Keep the detector's grid in sync with the microtones setting.
    t.setDivisions(settings.divisions);
    final accent = t.inTune ? Studio.green : Studio.amber;
    final name = settings.noteName(t.noteIndex);
    // Bright when a note is sounding (live); dimmed when holding the last
    // reading after the sound stops; faded when nothing has been read.
    final noteColor = !t.hasReading
        ? Studio.textDim
        : (t.live ? accent : accent.withValues(alpha: 0.5));

    return StudioScaffold(
      title: 'Tuner',
      subtitle: 'A = 440 Hz',
      showBack: false,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Big note (scales down so long names like "Mi koron" still fit)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                height: 104,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: Studio.numeric(92, color: noteColor).copyWith(
                          height: 1,
                          shadows: t.live
                              ? [
                                  Shadow(
                                    color: accent.withValues(alpha: 0.5),
                                    blurRadius: 28,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      if (t.noteIndex >= 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 12, left: 4),
                          child: Text(
                            '${t.octave}',
                            style: Studio.numeric(28, color: noteColor),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Status line (fixed height: its variants use different font
            // sizes, and any change would shift the gauge below).
            SizedBox(height: 22, child: Center(child: _StatusLine(tuner: t))),
            const SizedBox(height: 24),
            // Needle gauge
            KeyedSubtree(
              key: CoachKeys.tunerGauge,
              child: SizedBox(
                width: 300,
                height: 180,
                // Pitch updates arrive in discrete chunks; the tween glides
                // the needle between them so it sweeps instead of jumping.
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: t.needle),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  builder: (context, needle, _) => CustomPaint(
                    painter: _GaugePainter(
                      cents: needle,
                      inTune: t.inTune,
                      active: t.hasReading,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Frequency
            Text(
              t.hasReading ? '${t.frequency.toStringAsFixed(1)} Hz' : '—',
              style: Studio.numeric(16, color: Studio.textSecondary),
            ),
            const SizedBox(height: 24),
            KeyedSubtree(
              key: CoachKeys.tunerNotation,
              child: _NotationControls(settings: settings),
            ),
            const SizedBox(height: 16),
            _MicState(tuner: t),
          ],
        ),
      ),
    );
  }
}

class _NotationControls extends StatelessWidget {
  final AppSettings settings;
  const _NotationControls({required this.settings});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        StudioSegmented<NoteNaming>(
          selected: settings.noteNaming,
          options: const [
            (NoteNaming.letters, 'C D E'),
            (NoteNaming.solfege, 'Do Re Mi'),
          ],
          onChanged: settings.setNoteNaming,
        ),
        const SizedBox(height: 10),
        StudioSegmented<Accidental>(
          selected: settings.accidental,
          options: const [
            (Accidental.flats, '♭'),
            (Accidental.sharps, '♯'),
            (Accidental.both, '♭ ♯'),
          ],
          onChanged: settings.setAccidental,
        ),
        const SizedBox(height: 10),
        // Persian quarter-tones
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'QUARTER-TONES (KORON/SORI)',
              style: Studio.label.copyWith(fontSize: 10),
            ),
            const SizedBox(width: 10),
            StudioSwitch(
              value: settings.microtones,
              onChanged: settings.setMicrotones,
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  final Tuner tuner;
  const _StatusLine({required this.tuner});

  @override
  Widget build(BuildContext context) {
    if (!tuner.hasReading) {
      return Text(
        'PLAY A NOTE',
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 2,
          color: Studio.textDim,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    if (tuner.inTune) {
      return Text(
        tuner.live ? 'IN TUNE' : 'IN TUNE  ·  HOLD',
        style: TextStyle(
          fontSize: 13,
          letterSpacing: 2,
          color: Studio.green,
          fontWeight: FontWeight.w800,
        ),
      );
    }
    final sharp = tuner.cents > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          sharp ? '♯ SHARP' : '♭ FLAT',
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 2,
            color: Studio.amber,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${tuner.cents > 0 ? '+' : ''}${tuner.cents}¢',
          style: Studio.numeric(14, color: Studio.amber),
        ),
      ],
    );
  }
}

class _MicState extends StatelessWidget {
  final Tuner tuner;
  const _MicState({required this.tuner});

  @override
  Widget build(BuildContext context) {
    if (tuner.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          tuner.error!,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Studio.red),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          tuner.listening ? Icons.mic : Icons.mic_off,
          size: 14,
          color: tuner.listening ? Studio.amber : Studio.textDim,
        ),
        const SizedBox(width: 6),
        Text(tuner.listening ? 'Listening…' : 'Mic off', style: Studio.bodyDim),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double cents; // smoothed −50..50
  final bool inTune;
  final bool active;
  static const double _maxA = 50 * math.pi / 180; // ±50° sweep

  _GaugePainter({
    required this.cents,
    required this.inTune,
    required this.active,
  });

  /// Non-linear scale: expands the center and compresses the edges, so the
  /// few cents around "in tune" get most of the dial (like pro tuners).
  /// asinh-based, symmetric, monotonic: ±5¢ ≈ 32% of each side, ±10¢ ≈ 50%.
  static double _warp(double x) {
    const k = 12.0;
    double asinh(double y) => math.log(y + math.sqrt(y * y + 1));
    return x.sign * asinh(k * x.abs()) / asinh(k);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final pivot = Offset(w / 2, h - 6);
    final r = h * 0.92;
    final color = inTune
        ? Studio.green
        : (active ? Studio.amber : Studio.textDim);

    // Arc band
    final rect = Rect.fromCircle(center: pivot, radius: r);
    canvas.drawArc(
      rect,
      -math.pi / 2 - _maxA,
      2 * _maxA,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Studio.line,
    );

    // Highlight the (now wide) in-tune zone on the band.
    final zone = _warp(5 / 50) * _maxA;
    canvas.drawArc(
      rect,
      -math.pi / 2 - zone,
      2 * zone,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = Studio.green.withValues(alpha: 0.45),
    );

    void tick(int c, {required bool major, bool fine = false}) {
      final a = _warp(c / 50) * _maxA;
      final dir = Offset(math.sin(a), -math.cos(a));
      final inTuneTick = c.abs() <= 5;
      final inner = r - (major ? 18 : (fine ? 7 : 10));
      canvas.drawLine(
        pivot + dir * inner,
        pivot + dir * r,
        Paint()
          ..color = inTuneTick ? Studio.green : Studio.textDim
          ..strokeWidth = major ? 2.5 : (fine ? 1.0 : 1.5)
          ..strokeCap = StrokeCap.round,
      );
    }

    // Coarse ticks every 5 cents (major every 10)…
    for (int c = -50; c <= 50; c += 5) {
      tick(c, major: c % 10 == 0);
    }
    // …plus fine 2¢ ticks in the expanded center, where the room is.
    for (int c = -8; c <= 8; c += 2) {
      if (c % 5 != 0 && c != 0) tick(c, major: false, fine: true);
    }

    // Needle
    final na = _warp((cents / 50).clamp(-1.0, 1.0)) * _maxA;
    final ndir = Offset(math.sin(na), -math.cos(na));
    final tip = pivot + ndir * (r - 6);
    canvas.drawLine(
      pivot,
      tip,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawLine(
      pivot,
      tip,
      Paint()
        ..color = color
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(pivot, 8, Paint()..color = color);
    canvas.drawCircle(pivot, 3, Paint()..color = Studio.bg);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.cents != cents || old.inTune != inTune || old.active != active;
}
