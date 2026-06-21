import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/audio_controller.dart';
import '../services/library_store.dart';
import '../services/metronome.dart';
import '../ui/studio.dart';
import '../widgets/metronome_visual.dart';
import 'photo_viewer_screen.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  Track? _loadedPreset;
  AudioController? _audio;
  Metronome? _metro;
  StreamSubscription<void>? _loopSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _audio = context.read<AudioController>();
    _metro = context.read<Metronome>();
    // When the track loops back to the start, re-lock the click to beat 1 so it
    // stays aligned with the music's restart.
    _loopSub ??= _audio!.loopStream.listen((_) {
      if (_metro!.running) _metro!.restartFromDownbeat();
    });
  }

  @override
  void dispose() {
    _loopSub?.cancel();
    _audio?.pause();
    _metro?.stop();
    super.dispose();
  }

  void _syncPreset(Track? t) {
    if (t == null || identical(t, _loadedPreset)) return;
    _loadedPreset = t;
    final m = context.read<Metronome>();
    m.setBpm(t.bpm);
    m.setTimeSignature(t.beatsPerBar, t.timeSigDenominator);
    m.setSyncOffset(t.syncOffsetMs);
    m.setSpeed(t.speed);
    context.read<AudioController>().setSpeed(t.speed);
  }

  void _save(Track? t) {
    if (t == null) return;
    final m = context.read<Metronome>();
    t.bpm = m.bpm;
    t.beatsPerBar = m.beatsPerBar;
    t.timeSigDenominator = m.denominator;
    t.syncOffsetMs = m.syncOffsetMs;
    t.speed = context.read<AudioController>().speed;
    t.metronomeOn = m.running;
    context.read<LibraryStore>().updateTrack(t);
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final track = audio.current;
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPreset(track));

    return StudioScaffold(
      title: track?.title ?? 'Player',
      subtitle: 'Now Playing',
      showBack: true,
      bottomBar: track == null ? null : const _Transport(),
      body: track == null
          ? const Center(child: Text('No track loaded', style: Studio.bodyDim))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SpeedCard(onChanged: () => _save(track)),
                const SizedBox(height: 12),
                _MetronomeCard(onChanged: () => _save(track)),
                const SizedBox(height: 12),
                const _MixerCard(),
                const SizedBox(height: 12),
                _PhotosCard(track: track),
                const SizedBox(height: 12),
                _DoneCard(track: track),
              ],
            ),
    );
  }
}

// ───────── Done ─────────

class _DoneCard extends StatelessWidget {
  final Track track;
  const _DoneCard({required this.track});

  @override
  Widget build(BuildContext context) {
    context.watch<LibraryStore>();
    final done = track.done;
    return StudioCard(
      color: done ? Studio.amberSoft : Studio.surface,
      child: Row(
        children: [
          Icon(done ? Icons.verified : Icons.flag_outlined,
              color: done ? Studio.amber : Studio.textSecondary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(done ? 'Lesson completed' : 'Mark lesson as completed',
                    style: Studio.title),
                const SizedBox(height: 2),
                const Text('Tracks your progress through the book',
                    style: Studio.bodyDim),
              ],
            ),
          ),
          StudioSwitch(
            value: done,
            onChanged: (v) {
              track.done = v;
              context.read<LibraryStore>().updateTrack(track);
            },
          ),
        ],
      ),
    );
  }
}

// ───────── Photos ─────────

class _PhotosCard extends StatelessWidget {
  final Track track;
  const _PhotosCard({required this.track});

  Future<void> _add(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path != null) await library.addPhoto(track, path);
    }
  }

  void _open(BuildContext context, int i) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(track: track, initialIndex: i)));
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LibraryStore>();
    final photos = track.photoPaths;
    return StudioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Practice Photos',
              icon: Icons.photo_camera_back_outlined,
              trailing: photos.isNotEmpty
                  ? StudioButton(
                      label: 'View',
                      kind: StudioButtonKind.outline,
                      onTap: () => _open(context, 0))
                  : null),
          const SizedBox(height: 12),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                if (i == photos.length) {
                  return GestureDetector(
                    onTap: () => _add(context),
                    child: Container(
                      width: 84,
                      decoration: BoxDecoration(
                        color: Studio.surfaceHigh,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Studio.line),
                      ),
                      child: const Center(
                          child: Icon(Icons.add_a_photo_outlined,
                              color: Studio.amber)),
                    ),
                  );
                }
                return GestureDetector(
                  onTap: () => _open(context, i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(File(photos[i]),
                        width: 84, height: 84, fit: BoxFit.cover),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ───────── Speed ─────────

class _SpeedCard extends StatelessWidget {
  final VoidCallback onChanged;
  const _SpeedCard({required this.onChanged});

  String _fmt(double s) =>
      '${s == s.roundToDouble() ? s.toInt() : s}×';

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final metronome = context.read<Metronome>();
    const speeds = [1.0, 1.5, 2.0, 3.0];

    return StudioCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.speed, color: Studio.amber, size: 18),
          const SizedBox(width: 8),
          const Text('SPEED', style: Studio.label),
          const Spacer(),
          StudioSegmented<double>(
            selected: audio.speed,
            options: [for (final s in speeds) (s, _fmt(s))],
            onChanged: (s) {
              audio.setSpeed(s);
              metronome.setSpeed(s);
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}

// ───────── Metronome ─────────

class _MetronomeCard extends StatelessWidget {
  final VoidCallback onChanged;
  const _MetronomeCard({required this.onChanged});

  // (numerator, denominator) presets shown in the picker.
  static const _timeSigs = [
    (2, 4), (3, 4), (4, 4), (5, 4), (6, 4), (7, 4),
    (2, 2), (3, 8), (5, 8), (6, 8), (7, 8), (9, 8), (12, 8),
  ];

  void _timeSig(BuildContext context, Metronome m) {
    showStudioMenu(context, title: 'Time signature', actions: [
      for (final (n, d) in _timeSigs)
        StudioMenuAction('$n / $d', onTap: () {
          m.setTimeSignature(n, d);
          onChanged();
        }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final m = context.watch<Metronome>();
    return StudioCard(
      child: Column(
        children: [
          SectionLabel('Metronome',
              icon: Icons.av_timer,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('VISUAL', style: Studio.label.copyWith(fontSize: 10)),
                const SizedBox(width: 8),
                StudioSwitch(
                    value: m.visualEnabled, onChanged: m.setVisualEnabled),
              ])),
          if (m.visualEnabled) ...[
            const SizedBox(height: 10),
            MetronomeVisual(metronome: m),
            const SizedBox(height: 6),
          ] else
            const SizedBox(height: 10),
          BeatIndicator(metronome: m),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Stepper(icon: Icons.remove, onTap: () {
                m.nudgeBpm(-1);
                onChanged();
              }),
              const SizedBox(width: 24),
              NumericReadout('${m.bpm}', unit: 'BPM', size: 44),
              const SizedBox(width: 24),
              _Stepper(icon: Icons.add, onTap: () {
                m.nudgeBpm(1);
                onChanged();
              }),
            ],
          ),
          StudioSlider(
            min: 20,
            max: 300,
            value: m.bpm.toDouble(),
            onChanged: (v) {
              m.setBpm(v.round());
              onChanged();
            },
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              StudioButton(
                  label: 'Tap',
                  icon: Icons.touch_app_outlined,
                  kind: StudioButtonKind.ghost,
                  onTap: m.tap),
              StudioButton(
                  label: m.timeSigLabel,
                  kind: StudioButtonKind.ghost,
                  onTap: () => _timeSig(context, m)),
              StudioButton(
                  label: m.running ? 'Stop' : 'Click',
                  icon: m.running ? Icons.stop : Icons.play_arrow,
                  onTap: () {
                    m.toggle();
                    onChanged();
                  }),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(color: Studio.line, height: 1),
          ),
          _SyncRow(onChanged: onChanged),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _Stepper({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Studio.surfaceHigh,
            shape: BoxShape.circle,
            border: Border.all(color: Studio.line),
          ),
          child: Icon(icon, color: Studio.amber, size: 22),
        ),
      ),
    );
  }
}

class _SyncRow extends StatelessWidget {
  final VoidCallback onChanged;
  const _SyncRow({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final m = context.watch<Metronome>();
    final ms = m.syncOffsetMs;
    final label = ms == 0 ? 'IN SYNC' : '${ms > 0 ? '+' : ''}$ms ms';
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('SYNC OFFSET', style: Studio.label),
            const SizedBox(width: 10),
            Text(label,
                style: Studio.numeric(13,
                    color: ms == 0 ? Studio.textSecondary : Studio.amber)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            StudioIconButton(
                icon: Icons.remove,
                size: 18,
                color: Studio.amber,
                onTap: () {
                  m.nudgeSyncOffset(-5);
                  onChanged();
                }),
            Expanded(
              child: StudioSlider(
                min: -500,
                max: 500,
                value: ms.toDouble().clamp(-500, 500),
                onChanged: (v) {
                  m.setSyncOffset(v.round());
                  onChanged();
                },
              ),
            ),
            StudioIconButton(
                icon: Icons.add,
                size: 18,
                color: Studio.amber,
                onTap: () {
                  m.nudgeSyncOffset(5);
                  onChanged();
                }),
          ],
        ),
        const Text('Nudge until the click lines up with the music',
            style: Studio.bodyDim),
      ],
    );
  }
}

// ───────── Mixer ─────────

class _MixerCard extends StatelessWidget {
  const _MixerCard();

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final m = context.watch<Metronome>();
    return StudioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Mixer', icon: Icons.tune),
          const SizedBox(height: 12),
          _Fader(
              icon: Icons.music_note,
              label: 'Music',
              muted: audio.muted,
              volume: audio.volume,
              accent: Studio.amber,
              onMute: audio.toggleMute,
              onVolume: audio.setVolume),
          const SizedBox(height: 10),
          _Fader(
              icon: Icons.av_timer,
              label: 'Metronome',
              muted: m.muted,
              volume: m.volume,
              accent: Studio.teal,
              onMute: m.toggleMute,
              onVolume: m.setVolume),
        ],
      ),
    );
  }
}

class _Fader extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool muted;
  final double volume;
  final Color accent;
  final VoidCallback onMute;
  final ValueChanged<double> onVolume;
  const _Fader({
    required this.icon,
    required this.label,
    required this.muted,
    required this.volume,
    required this.accent,
    required this.onMute,
    required this.onVolume,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        StudioIconButton(
            icon: muted ? Icons.volume_off : icon,
            size: 20,
            color: muted ? Studio.red : accent,
            onTap: onMute),
        SizedBox(width: 78, child: Text(label, style: Studio.body)),
        Expanded(
          child: StudioSlider(
              value: muted ? 0 : volume,
              accent: accent,
              onChanged: muted ? null : onVolume),
        ),
        SizedBox(
          width: 36,
          child: Text('${(volume * 100).round()}',
              textAlign: TextAlign.end,
              style: Studio.numeric(12, color: Studio.textSecondary)),
        ),
      ],
    );
  }
}

// ───────── Transport ─────────

class _Transport extends StatelessWidget {
  const _Transport();

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final metronome = context.read<Metronome>();

    Future<void> togglePlay() async {
      if (audio.isPlaying) {
        await audio.pause();
        metronome.pause(); // freeze phase so resume stays in sync
      } else {
        // Resume from the frozen phase, or start fresh if not yet running.
        if (metronome.running) {
          metronome.resume();
        } else {
          metronome.start();
        }
        await audio.play();
      }
    }

    Future<void> restart() async {
      await audio.seek(Duration.zero);
      metronome.stop();
      metronome.start();
      await audio.play();
    }

    return Container(
      decoration: const BoxDecoration(
        color: Studio.surface,
        border: Border(top: BorderSide(color: Studio.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<Duration>(
              stream: audio.positionStream,
              builder: (context, snap) {
                final pos = snap.data ?? Duration.zero;
                final dur = audio.duration ?? Duration.zero;
                final maxMs = dur.inMilliseconds.toDouble();
                return Row(
                  children: [
                    Text(_fmt(pos),
                        style:
                            Studio.numeric(11, color: Studio.textSecondary)),
                    Expanded(
                      child: StudioSlider(
                        min: 0,
                        max: maxMs == 0 ? 1 : maxMs,
                        value: pos.inMilliseconds.toDouble(),
                        onChanged: (v) =>
                            audio.seek(Duration(milliseconds: v.round())),
                      ),
                    ),
                    Text(_fmt(dur),
                        style:
                            Studio.numeric(11, color: Studio.textSecondary)),
                  ],
                );
              },
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                // Left controls, pushed toward the centered play button.
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      StudioIconButton(
                          icon: Icons.replay,
                          tooltip: 'Restart both from the top',
                          onTap: restart),
                      const SizedBox(width: 10),
                      StudioIconButton(
                          icon: Icons.skip_previous,
                          size: 28,
                          onTap: audio.prev),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                _PlayButton(
                    playing: audio.isPlaying,
                    metronome: metronome,
                    onTap: togglePlay),
                const SizedBox(width: 16),
                // Right controls, balanced against the left group.
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      StudioIconButton(
                          icon: Icons.skip_next,
                          size: 28,
                          onTap: audio.hasNext ? audio.next : null),
                    ],
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

class _PlayButton extends StatefulWidget {
  final bool playing;
  final Metronome metronome;
  final VoidCallback onTap;
  const _PlayButton(
      {required this.playing, required this.metronome, required this.onTap});

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 320));
  StreamSubscription<int>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.metronome.beatStream.listen((_) {
      if (mounted) _pulse.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final t = 1 - _pulse.value; // 1 → 0
            return Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: Studio.amber,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Studio.amber.withValues(alpha: 0.55 * t),
                    blurRadius: 10 + 18 * (1 - t),
                    spreadRadius: 2 + 6 * (1 - t),
                  ),
                ],
              ),
              child: child,
            );
          },
          child: Icon(widget.playing ? Icons.pause : Icons.play_arrow,
              color: Studio.bg, size: 30),
        ),
      ),
    );
  }
}
