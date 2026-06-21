import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings.dart';
import '../services/tuner.dart';
import '../ui/studio.dart';

const Color _green = Color(0xFF35D06A);

class TunerScreen extends StatefulWidget {
  const TunerScreen({super.key});

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> {
  Tuner? _tuner;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tuner = context.read<Tuner>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tuner?.start());
  }

  @override
  void dispose() {
    _tuner?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<Tuner>();
    final settings = context.watch<AppSettings>();
    // Keep the detector's grid in sync with the microtones setting.
    t.setDivisions(settings.divisions);
    final accent = t.inTune ? _green : Studio.amber;
    final name = settings.noteName(t.noteIndex);
    // Bright when a note is sounding (live); dimmed when holding the last
    // reading after the sound stops; faded when nothing has been read.
    final noteColor = !t.hasReading
        ? Studio.textDim
        : (t.live ? accent : accent.withValues(alpha: 0.5));

    return StudioScaffold(
      title: 'Tuner',
      subtitle: 'A = 440 Hz',
      showBack: true,
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
                                      blurRadius: 28)
                                ]
                              : null,
                        ),
                      ),
                      if (t.noteIndex >= 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 12, left: 4),
                          child: Text('${t.octave}',
                              style: Studio.numeric(28, color: noteColor)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Status line
            _StatusLine(tuner: t),
            const SizedBox(height: 24),
            // Needle gauge
            SizedBox(
              width: 300,
              height: 180,
              child: CustomPaint(
                painter: _GaugePainter(
                  cents: t.needle,
                  inTune: t.inTune,
                  active: t.hasReading,
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
            _NotationControls(settings: settings),
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
            Text('QUARTER-TONES (KORON/SORI)',
                style: Studio.label.copyWith(fontSize: 10)),
            const SizedBox(width: 10),
            StudioSwitch(
                value: settings.microtones, onChanged: settings.setMicrotones),
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
      return const Text('PLAY A NOTE',
          style: TextStyle(
              fontSize: 12,
              letterSpacing: 2,
              color: Studio.textDim,
              fontWeight: FontWeight.w700));
    }
    if (tuner.inTune) {
      return Text(tuner.live ? 'IN TUNE' : 'IN TUNE  ·  HOLD',
          style: const TextStyle(
              fontSize: 13,
              letterSpacing: 2,
              color: _green,
              fontWeight: FontWeight.w800));
    }
    final sharp = tuner.cents > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(sharp ? '♯ SHARP' : '♭ FLAT',
            style: const TextStyle(
                fontSize: 12,
                letterSpacing: 2,
                color: Studio.amber,
                fontWeight: FontWeight.w700)),
        const SizedBox(width: 10),
        Text('${tuner.cents > 0 ? '+' : ''}${tuner.cents}¢',
            style: Studio.numeric(14, color: Studio.amber)),
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
        child: Text(tuner.error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Studio.red)),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(tuner.listening ? Icons.mic : Icons.mic_off,
            size: 14,
            color: tuner.listening ? Studio.amber : Studio.textDim),
        const SizedBox(width: 6),
        Text(tuner.listening ? 'Listening…' : 'Mic off',
            style: Studio.bodyDim),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double cents; // smoothed −50..50
  final bool inTune;
  final bool active;
  static const double _maxA = 50 * math.pi / 180; // ±50° sweep

  _GaugePainter(
      {required this.cents, required this.inTune, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final pivot = Offset(w / 2, h - 6);
    final r = h * 0.92;
    final color =
        inTune ? _green : (active ? Studio.amber : Studio.textDim);

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

    // Ticks every 5 cents (major every 10)
    for (int c = -50; c <= 50; c += 5) {
      final a = c / 50 * _maxA;
      final dir = Offset(math.sin(a), -math.cos(a));
      final major = c % 10 == 0;
      final inTuneTick = c.abs() <= 5;
      final inner = r - (major ? 18 : 10);
      canvas.drawLine(
        pivot + dir * inner,
        pivot + dir * r,
        Paint()
          ..color = inTuneTick ? _green : Studio.textDim
          ..strokeWidth = major ? 2.5 : 1.5
          ..strokeCap = StrokeCap.round,
      );
    }

    // Needle
    final na = (cents / 50).clamp(-1.0, 1.0) * _maxA;
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
    canvas.drawCircle(
        pivot, 3, Paint()..color = Studio.bg);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.cents != cents || old.inTune != inTune || old.active != active;
}
