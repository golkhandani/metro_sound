import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../services/library_store.dart';
import '../services/metronome.dart';
import '../services/recorder.dart';
import '../services/tuner.dart';
import '../ui/studio.dart';

/// Full recording studio: record / pause / stop / reset, a count-in and
/// click-track via the metronome, a live level meter, and a trim step before
/// saving the take into a book.
class RecordScreen extends StatefulWidget {
  final String bookId;
  final String bookTitle;
  const RecordScreen({
    super.key,
    required this.bookId,
    required this.bookTitle,
  });

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final Recorder _rec = Recorder();
  final AudioPlayer _preview = AudioPlayer();

  // Settings
  bool _countIn = true;
  bool _clickWhileRecording = false;

  // Count-in
  bool _counting = false;
  int _countLeft = 0;

  // Trim (fractions of the take)
  double _trimStart = 0;
  double _trimEnd = 1;

  late Metronome _metro;

  @override
  void initState() {
    super.initState();
    _rec.addListener(_onRec);
    _preview.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _metro = context.read<Metronome>(); // cached for safe use in dispose()
  }

  void _onRec() => setState(() {});

  @override
  void dispose() {
    _rec.removeListener(_onRec);
    _metro.stop();
    _rec.dispose();
    _preview.dispose();
    super.dispose();
  }

  // ─── Transport ───

  Future<void> _record() async {
    // The tuner shares the one native mic engine — make sure it's released.
    context.read<Tuner>().stop();
    if (_countIn) {
      await _runCountIn();
      if (!mounted) return;
    }
    // Release the playback session the metronome held, let it settle, then claim
    // the mic for recording.
    _metro.stop();
    await Future.delayed(const Duration(milliseconds: 120));
    final ok = await _rec.start();
    if (!ok) return;
    // Resume the click now that capture owns the audio session.
    if (_clickWhileRecording && mounted) _metro.start();
  }

  Future<void> _runCountIn() async {
    final beats = _metro.beatsPerBar;
    setState(() {
      _counting = true;
      _countLeft = beats;
    });
    _metro.stop();
    _metro.start();
    final sub = _metro.beatStream.listen((_) {
      if (mounted && _countLeft > 0) setState(() => _countLeft -= 1);
    });
    final beatMs = (60000 / (_metro.bpm <= 0 ? 60 : _metro.bpm)).round();
    await Future.delayed(Duration(milliseconds: beatMs * beats));
    await sub.cancel();
    // _record() stops the metronome and reclaims the session after this.
    if (mounted) setState(() => _counting = false);
  }

  Future<void> _pauseResume() async {
    if (_rec.isRecording) {
      await _rec.pause();
      _metro.stop();
    } else if (_rec.isPaused) {
      await _rec.resume();
      if (_clickWhileRecording && !_metro.running) _metro.start();
    }
  }

  Future<void> _stop() async {
    _metro.stop();
    await _rec.stop();
    setState(() {
      _trimStart = 0;
      _trimEnd = 1;
    });
  }

  Future<void> _reset() async {
    await _preview.stop();
    _metro.stop();
    await _rec.reset();
    setState(() {
      _trimStart = 0;
      _trimEnd = 1;
      _counting = false;
    });
  }

  Future<void> _togglePreview() async {
    if (_preview.playing) {
      await _preview.pause();
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final f = File(p.join(dir.path, 'take_preview.wav'));
      await f.writeAsBytes(
        _rec.exportWav(startFrac: _trimStart, endFrac: _trimEnd),
      );
      await _preview.setFilePath(f.path);
      await _preview.play();
    } catch (e) {
      if (mounted) showToast(context, 'Preview failed');
    }
  }

  Future<void> _save() async {
    final name = await studioPrompt(
      context,
      title: 'Name this recording',
      initial: 'Recording',
      hint: 'e.g. Daramad — take 1',
    );
    if (name == null || !mounted) return;
    final wav = _rec.exportWav(startFrac: _trimStart, endFrac: _trimEnd);
    await context.read<LibraryStore>().addRecordedTrack(
      widget.bookId,
      wav,
      name,
    );
    if (mounted) Navigator.of(context).pop();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ─── UI ───

  @override
  Widget build(BuildContext context) {
    return StudioScaffold(
      title: 'Record',
      subtitle: widget.bookTitle,
      showBack: true,
      actions: [
        StudioIconButton(
          icon: Icons.tune,
          tooltip: 'Recording settings',
          onTap: _openSettings,
        ),
      ],
      body: Padding(padding: const EdgeInsets.all(16), child: _body()),
    );
  }

  Widget _body() {
    if (_rec.error != null && _rec.state == RecState.idle) {
      return _errorView();
    }
    if (_rec.hasTake) return _reviewView();
    return _captureView();
  }

  Widget _errorView() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.mic_off_outlined, size: 48, color: Studio.red),
        const SizedBox(height: 14),
        Text(_rec.error!, textAlign: TextAlign.center, style: Studio.bodyDim),
        const SizedBox(height: 20),
        StudioButton(label: 'Try again', onTap: _reset),
      ],
    ),
  );

  Widget _captureView() {
    final recording = _rec.isRecording;
    final paused = _rec.isPaused;
    final active = recording || paused;
    return Column(
      children: [
        const Spacer(),
        if (_counting)
          Text('$_countLeft', style: Studio.numeric(96, color: Studio.amber))
        else
          NumericReadout(
            _fmt(_rec.elapsed),
            unit: active ? (paused ? 'PAUSED' : 'RECORDING') : 'READY',
            size: 56,
            color: recording ? Studio.amber : Studio.textPrimary,
          ),
        const SizedBox(height: 24),
        _LevelMeter(level: recording ? _rec.level : 0),
        const Spacer(),
        if (!active && !_counting)
          _RoundButton(
            icon: Icons.fiber_manual_record,
            color: Studio.red,
            size: 84,
            onTap: _counting ? null : _record,
          )
        else if (!_counting)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _RoundButton(
                icon: Icons.refresh,
                color: Studio.textSecondary,
                size: 56,
                onTap: _reset,
                label: 'Reset',
              ),
              _RoundButton(
                icon: paused ? Icons.fiber_manual_record : Icons.pause,
                color: paused ? Studio.red : Studio.amber,
                size: 84,
                onTap: _pauseResume,
                label: paused ? 'Resume' : 'Pause',
              ),
              _RoundButton(
                icon: Icons.stop,
                color: Studio.textPrimary,
                size: 56,
                onTap: _stop,
                label: 'Stop',
              ),
            ],
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _reviewView() {
    final total = _rec.takeDuration;
    final selMs = ((_trimEnd - _trimStart) * total.inMilliseconds).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const SectionLabel('Trim', icon: Icons.content_cut),
        const SizedBox(height: 12),
        _TrimWaveform(
          bars: _rec.waveform(80),
          startFrac: _trimStart,
          endFrac: _trimEnd,
          onChanged: (s, e) {
            _preview.stop();
            setState(() {
              _trimStart = s;
              _trimEnd = e;
            });
          },
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Selection ${_fmt(Duration(milliseconds: selMs))}',
              style: Studio.bodyDim,
            ),
            Text('of ${_fmt(total)}', style: Studio.bodyDim),
          ],
        ),
        const SizedBox(height: 20),
        Center(
          child: _RoundButton(
            icon: _preview.playing ? Icons.pause : Icons.play_arrow,
            color: Studio.amber,
            size: 64,
            onTap: _togglePreview,
            label: 'Preview',
          ),
        ),
        const Spacer(),
        Row(
          children: [
            Expanded(
              child: StudioButton(
                label: 'Re-record',
                icon: Icons.refresh,
                kind: StudioButtonKind.ghost,
                onTap: _reset,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StudioButton(
                label: 'Save',
                icon: Icons.check,
                onTap: _save,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ─── Settings sheet ───

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final m = context.read<Metronome>();
          void refresh() {
            setSheet(() {});
            setState(() {});
          }

          return Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
            decoration: BoxDecoration(
              color: Studio.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Studio.line),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Recording settings', icon: Icons.tune),
                  const SizedBox(height: 16),
                  // Tempo (drives count-in + click)
                  Row(
                    children: [
                      Expanded(child: Text('Tempo', style: Studio.title)),
                      _MiniStep(
                        icon: Icons.remove,
                        onTap: () {
                          m.nudgeBpm(-1);
                          refresh();
                        },
                      ),
                      SizedBox(
                        width: 64,
                        child: Center(
                          child: Text(
                            '${m.bpm}',
                            style: Studio.numeric(18, color: Studio.amber),
                          ),
                        ),
                      ),
                      _MiniStep(
                        icon: Icons.add,
                        onTap: () {
                          m.nudgeBpm(1);
                          refresh();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _SheetToggle(
                    title: 'Count-in',
                    subtitle: 'One bar of clicks before recording starts',
                    value: _countIn,
                    onChanged: (v) {
                      _countIn = v;
                      refresh();
                    },
                  ),
                  _SheetToggle(
                    title: 'Click while recording',
                    subtitle: 'Hear the metronome as you play (use headphones)',
                    value: _clickWhileRecording,
                    onChanged: (v) {
                      _clickWhileRecording = v;
                      refresh();
                    },
                  ),
                  const SizedBox(height: 14),
                  Text('QUALITY', style: Studio.label),
                  const SizedBox(height: 8),
                  Opacity(
                    opacity: _rec.state == RecState.idle ? 1 : 0.4,
                    child: IgnorePointer(
                      ignoring: _rec.state != RecState.idle,
                      child: StudioSegmented<int>(
                        options: const [
                          (44100, 'High 44k'),
                          (22050, 'Voice 22k'),
                        ],
                        selected: _rec.sampleRate,
                        onChanged: (v) {
                          _rec.setSampleRate(v);
                          refresh();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Pieces ───

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback? onTap;
  final String? label;
  const _RoundButton({
    required this.icon,
    required this.color,
    required this.size,
    this.onTap,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Pressable(
      onTap: onTap ?? () {},
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Studio.surfaceHigh,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 14),
            ],
          ),
          child: Icon(icon, color: color, size: size * 0.42),
        ),
      ),
    );
    if (label == null) return btn;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn,
        const SizedBox(height: 8),
        Text(label!, style: Studio.bodyDim),
      ],
    );
  }
}

class _LevelMeter extends StatelessWidget {
  final double level; // 0..1
  const _LevelMeter({required this.level});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.mic, size: 16, color: Studio.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(color: Studio.surfaceHigh),
                  FractionallySizedBox(
                    widthFactor: level.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Studio.teal,
                            level > 0.85 ? Studio.red : Studio.amber,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniStep extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MiniStep({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Studio.surfaceHigh,
          shape: BoxShape.circle,
          border: Border.all(color: Studio.line),
        ),
        child: Icon(icon, color: Studio.amber, size: 18),
      ),
    );
  }
}

class _SheetToggle extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SheetToggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Studio.title),
                const SizedBox(height: 2),
                Text(subtitle, style: Studio.bodyDim),
              ],
            ),
          ),
          StudioSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _TrimWaveform extends StatefulWidget {
  final List<double> bars;
  final double startFrac;
  final double endFrac;
  final void Function(double start, double end) onChanged;
  const _TrimWaveform({
    required this.bars,
    required this.startFrac,
    required this.endFrac,
    required this.onChanged,
  });

  @override
  State<_TrimWaveform> createState() => _TrimWaveformState();
}

class _TrimWaveformState extends State<_TrimWaveform> {
  int _active = 0; // -1 left handle, 1 right handle

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        double fracAt(double dx) => (dx / w).clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) {
            final f = fracAt(d.localPosition.dx);
            _active = (f - widget.startFrac).abs() <= (f - widget.endFrac).abs()
                ? -1
                : 1;
            _apply(f);
          },
          onHorizontalDragUpdate: (d) => _apply(fracAt(d.localPosition.dx)),
          child: SizedBox(
            height: 120,
            child: CustomPaint(
              size: Size(w, 120),
              painter: _TrimPainter(
                bars: widget.bars,
                startFrac: widget.startFrac,
                endFrac: widget.endFrac,
              ),
            ),
          ),
        );
      },
    );
  }

  void _apply(double f) {
    if (_active == -1) {
      widget.onChanged(f.clamp(0.0, widget.endFrac - 0.02), widget.endFrac);
    } else {
      widget.onChanged(widget.startFrac, f.clamp(widget.startFrac + 0.02, 1.0));
    }
  }
}

class _TrimPainter extends CustomPainter {
  final List<double> bars;
  final double startFrac;
  final double endFrac;
  _TrimPainter({
    required this.bars,
    required this.startFrac,
    required this.endFrac,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final n = bars.length;
    if (n == 0) return;
    final bw = size.width / n;
    for (var i = 0; i < n; i++) {
      final f = (i + 0.5) / n;
      final inSel = f >= startFrac && f <= endFrac;
      final h = (size.height * 0.92) * (0.04 + 0.96 * bars[i]);
      final x = i * bw + bw / 2;
      canvas.drawLine(
        Offset(x, mid - h / 2),
        Offset(x, mid + h / 2),
        Paint()
          ..color = inSel ? Studio.amber : Studio.line
          ..strokeWidth = (bw * 0.7).clamp(1.0, 3.0),
      );
    }
    // Handles
    final hx1 = startFrac * size.width;
    final hx2 = endFrac * size.width;
    final hp = Paint()..color = Studio.teal;
    for (final hx in [hx1, hx2]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(hx.clamp(0, size.width - 4) - 2, 0, 4, size.height),
          const Radius.circular(2),
        ),
        hp,
      );
    }
    // Dim outside selection
    final dim = Paint()..color = Studio.bg.withValues(alpha: 0.45);
    canvas.drawRect(Rect.fromLTWH(0, 0, hx1, size.height), dim);
    canvas.drawRect(Rect.fromLTWH(hx2, 0, size.width - hx2, size.height), dim);
  }

  @override
  bool shouldRepaint(covariant _TrimPainter old) =>
      old.startFrac != startFrac || old.endFrac != endFrac || old.bars != bars;
}
