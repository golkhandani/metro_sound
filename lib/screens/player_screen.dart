import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/audio_controller.dart';
import '../services/library_store.dart';
import '../services/metronome.dart';
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Capture references so we can stop playback safely in dispose().
    _audio = context.read<AudioController>();
    _metro = context.read<Metronome>();
  }

  @override
  void dispose() {
    // Leaving the player (back to the library) stops music + metronome.
    _audio?.pause();
    _metro?.stop();
    super.dispose();
  }

  /// Load this track's saved metronome preset into the metronome engine.
  void _syncPreset(Track? track) {
    if (track == null || identical(track, _loadedPreset)) return;
    _loadedPreset = track;
    final m = context.read<Metronome>();
    m.setBpm(track.bpm);
    m.setBeatsPerBar(track.beatsPerBar);
    m.setSyncOffset(track.syncOffsetMs);
  }

  void _savePreset(Track? track) {
    if (track == null) return;
    final m = context.read<Metronome>();
    track.bpm = m.bpm;
    track.beatsPerBar = m.beatsPerBar;
    track.syncOffsetMs = m.syncOffsetMs;
    track.metronomeOn = m.running;
    context.read<LibraryStore>().updateTrack(track);
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final track = audio.current;
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPreset(track));

    return Scaffold(
      appBar: AppBar(
        title: Text(track?.title ?? 'Player'),
      ),
      body: track == null
          ? const Center(child: Text('No track loaded'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _DoneTile(track: track),
                  const SizedBox(height: 12),
                  _PhotosSection(track: track),
                  const SizedBox(height: 12),
                  _MetronomeSection(onChanged: () => _savePreset(track)),
                  const SizedBox(height: 16),
                  const _MixerSection(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
      bottomNavigationBar: track == null ? null : const _TransportBar(),
    );
  }
}

// ───────────────────────── Done / progress ─────────────────────────

class _DoneTile extends StatelessWidget {
  final Track track;
  const _DoneTile({required this.track});

  @override
  Widget build(BuildContext context) {
    // Watch the library so the tile reflects the saved state immediately.
    context.watch<LibraryStore>();
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: track.done
          ? cs.primaryContainer
          : cs.surfaceContainerHighest.withValues(alpha: 0.4),
      child: CheckboxListTile(
        value: track.done,
        onChanged: (v) {
          track.done = v ?? false;
          context.read<LibraryStore>().updateTrack(track);
        },
        secondary: Icon(
          track.done ? Icons.verified : Icons.check_circle_outline,
          color: track.done ? cs.primary : cs.outline,
        ),
        title: Text(
          track.done
              ? "I've completed this lesson"
              : 'Mark this lesson as completed',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: const Text('Tracks your progress through the book'),
        controlAffinity: ListTileControlAffinity.trailing,
      ),
    );
  }
}

// ───────────────────────── Practice photos ─────────────────────────

class _PhotosSection extends StatelessWidget {
  final Track track;
  const _PhotosSection({required this.track});

  Future<void> _addPhoto(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path != null) await library.addPhoto(track, path);
    }
  }

  void _openViewer(BuildContext context, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(track: track, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LibraryStore>(); // rebuild when photos change
    final cs = Theme.of(context).colorScheme;
    final photos = track.photoPaths;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.photo_library, color: cs.primary),
                const SizedBox(width: 8),
                Text('Practice photos',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (photos.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _openViewer(context, 0),
                    icon: const Icon(Icons.fullscreen, size: 18),
                    label: const Text('View'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  if (i == photos.length) {
                    // "Add photo" tile
                    return InkWell(
                      onTap: () => _addPhoto(context),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 96,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo, color: cs.primary),
                            const SizedBox(height: 4),
                            Text('Add',
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    );
                  }
                  return GestureDetector(
                    onTap: () => _openViewer(context, i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        File(photos[i]),
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Transport ─────────────────────────

class _TransportBar extends StatelessWidget {
  const _TransportBar();

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final metronome = context.read<Metronome>();

    // Main transport drives music and metronome together.
    Future<void> togglePlay() async {
      if (audio.isPlaying) {
        await audio.pause();
        metronome.stop();
      } else {
        metronome.start(); // start the click on beat 1, in sync with the music
        await audio.play();
      }
    }

    // Reset: jump both back to the top and play music + metronome from beat 1.
    Future<void> restart() async {
      await audio.seek(Duration.zero);
      metronome.stop(); // reset the beat counter...
      metronome.start(); // ...then restart on beat 1
      await audio.play();
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<Duration>(
              stream: audio.positionStream,
              builder: (context, snap) {
                final pos = snap.data ?? Duration.zero;
                final dur = audio.duration ?? Duration.zero;
                final maxMs = dur.inMilliseconds.toDouble();
                final value =
                    maxMs == 0 ? 0.0 : pos.inMilliseconds.clamp(0, maxMs).toDouble();
                return Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 7),
                      ),
                      child: Slider(
                        min: 0,
                        max: maxMs == 0 ? 1 : maxMs,
                        value: value,
                        onChanged: (v) =>
                            audio.seek(Duration(milliseconds: v.round())),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_fmt(pos),
                              style: Theme.of(context).textTheme.bodySmall),
                          Text(_fmt(dur),
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 28,
                  tooltip: 'Restart music + metronome together',
                  onPressed: restart,
                  icon: const Icon(Icons.restart_alt),
                ),
                const SizedBox(width: 4),
                IconButton(
                  iconSize: 32,
                  onPressed: audio.prev,
                  icon: const Icon(Icons.skip_previous),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: togglePlay,
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(18),
                  ),
                  child: Icon(
                    audio.isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  iconSize: 32,
                  onPressed: audio.hasNext ? audio.next : null,
                  icon: const Icon(Icons.skip_next),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Metronome ─────────────────────────

class _MetronomeSection extends StatelessWidget {
  final VoidCallback onChanged;
  const _MetronomeSection({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final m = context.watch<Metronome>();
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.av_timer, color: cs.primary),
                const SizedBox(width: 8),
                Text('Metronome',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                // Visual on/off toggle
                Row(
                  children: [
                    const Text('Visual'),
                    Switch(
                      value: m.visualEnabled,
                      onChanged: m.setVisualEnabled,
                    ),
                  ],
                ),
              ],
            ),
            if (m.visualEnabled) ...[
              const SizedBox(height: 4),
              MetronomeVisual(metronome: m),
              const SizedBox(height: 8),
            ],
            BeatIndicator(metronome: m),
            const SizedBox(height: 12),
            // BPM control
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  onPressed: () {
                    m.nudgeBpm(-1);
                    onChanged();
                  },
                  icon: const Icon(Icons.remove),
                ),
                const SizedBox(width: 16),
                Column(
                  children: [
                    Text('${m.bpm}',
                        style: Theme.of(context)
                            .textTheme
                            .displaySmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Text('BPM'),
                  ],
                ),
                const SizedBox(width: 16),
                IconButton.filledTonal(
                  onPressed: () {
                    m.nudgeBpm(1);
                    onChanged();
                  },
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            Slider(
              min: 20,
              max: 300,
              value: m.bpm.toDouble(),
              label: '${m.bpm}',
              divisions: 280,
              onChanged: (v) {
                m.setBpm(v.round());
                onChanged();
              },
            ),
            const SizedBox(height: 4),
            _SyncOffsetControl(onChanged: onChanged),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: m.tap,
                  icon: const Icon(Icons.touch_app),
                  label: const Text('Tap'),
                ),
                _TimeSigSelector(onChanged: onChanged),
                FilledButton.icon(
                  onPressed: () {
                    m.toggle();
                    onChanged();
                  },
                  icon: Icon(m.running ? Icons.stop : Icons.play_arrow),
                  label: Text(m.running ? 'Stop' : 'Start'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncOffsetControl extends StatelessWidget {
  final VoidCallback onChanged;
  const _SyncOffsetControl({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final m = context.watch<Metronome>();
    final cs = Theme.of(context).colorScheme;
    final ms = m.syncOffsetMs;
    final label = ms == 0 ? 'in sync' : '${ms > 0 ? '+' : ''}$ms ms';

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sync, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Text('Sync offset', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(width: 8),
            Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: ms == 0 ? cs.outline : cs.primary,
                    )),
            if (ms != 0) ...[
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Reset to 0',
                onPressed: () {
                  m.setSyncOffset(0);
                  onChanged();
                },
                icon: const Icon(Icons.restart_alt, size: 18),
              ),
            ],
          ],
        ),
        Row(
          children: [
            IconButton.outlined(
              visualDensity: VisualDensity.compact,
              tooltip: 'Click 5 ms earlier',
              onPressed: () {
                m.nudgeSyncOffset(-5);
                onChanged();
              },
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Slider(
                min: -500,
                max: 500,
                divisions: 200, // 5 ms steps
                value: ms.toDouble().clamp(-500, 500),
                label: '$ms ms',
                onChanged: (v) {
                  m.setSyncOffset(v.round());
                  onChanged();
                },
              ),
            ),
            IconButton.outlined(
              visualDensity: VisualDensity.compact,
              tooltip: 'Click 5 ms later',
              onPressed: () {
                m.nudgeSyncOffset(5);
                onChanged();
              },
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        Text(
          'Nudge until the click lines up with the music',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline),
        ),
      ],
    );
  }
}

class _TimeSigSelector extends StatelessWidget {
  final VoidCallback onChanged;
  const _TimeSigSelector({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final m = context.watch<Metronome>();
    return DropdownButton<int>(
      value: m.beatsPerBar,
      underline: const SizedBox.shrink(),
      items: const [2, 3, 4, 5, 6, 7]
          .map((b) => DropdownMenuItem(value: b, child: Text('$b/4')))
          .toList(),
      onChanged: (v) {
        if (v != null) {
          m.setBeatsPerBar(v);
          onChanged();
        }
      },
    );
  }
}

// ───────────────────────── Mixer ─────────────────────────

class _MixerSection extends StatelessWidget {
  const _MixerSection();

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final m = context.watch<Metronome>();
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: cs.primary),
                const SizedBox(width: 8),
                Text('Mixer', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            _MixRow(
              icon: Icons.music_note,
              label: 'Music',
              muted: audio.muted,
              volume: audio.volume,
              onMute: audio.toggleMute,
              onVolume: audio.setVolume,
            ),
            _MixRow(
              icon: Icons.av_timer,
              label: 'Metronome',
              muted: m.muted,
              volume: m.volume,
              onMute: m.toggleMute,
              onVolume: m.setVolume,
            ),
          ],
        ),
      ),
    );
  }
}

class _MixRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool muted;
  final double volume;
  final VoidCallback onMute;
  final ValueChanged<double> onVolume;

  const _MixRow({
    required this.icon,
    required this.label,
    required this.muted,
    required this.volume,
    required this.onMute,
    required this.onVolume,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onMute,
          icon: Icon(muted ? Icons.volume_off : icon,
              color: muted ? Theme.of(context).colorScheme.error : null),
        ),
        SizedBox(
          width: 86,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: Slider(
            min: 0,
            max: 1,
            value: muted ? 0 : volume,
            onChanged: muted ? null : onVolume,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text('${(volume * 100).round()}',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}
