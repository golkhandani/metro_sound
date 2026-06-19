import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../models/track.dart';
import '../services/audio_controller.dart';
import '../services/library_store.dart';
import '../ui/studio.dart';
import 'player_screen.dart';

class BookScreen extends StatelessWidget {
  final Book book;
  const BookScreen({super.key, required this.book});

  Future<void> _import(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'wav', 'aac', 'flac', 'ogg'],
    );
    if (result == null) return;
    final paths =
        result.files.map((f) => f.path).whereType<String>().toList();
    await library.importAudioFiles(book.id, paths);
  }

  void _openPlayer(BuildContext context, List<Track> tracks, int i) {
    context.read<AudioController>().openQueue(tracks, i);
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final tracks = library.tracksForBook(book.id);
    final done = tracks.where((t) => t.done).length;

    return StudioScaffold(
      title: book.title,
      subtitle: tracks.isEmpty ? 'Empty' : '$done of ${tracks.length} done',
      showBack: true,
      actions: [
        if (tracks.isNotEmpty)
          StudioIconButton(
              icon: Icons.play_arrow_rounded,
              tooltip: 'Play all',
              color: Studio.amber,
              onTap: () => _openPlayer(context, tracks, 0)),
        StudioIconButton(
            icon: Icons.add,
            tooltip: 'Import audio',
            onTap: () => _import(context)),
      ],
      body: tracks.isEmpty
          ? _Empty(onImport: () => _import(context))
          : Column(
              children: [
                _ProgressBar(done: done, total: tracks.length),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    itemCount: tracks.length,
                    itemBuilder: (context, i) => _TrackRow(
                      track: tracks[i],
                      index: i,
                      onOpen: () => _openPlayer(context, tracks, i),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final int done;
  final int total;
  const _ProgressBar({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : done / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Text('${(pct * 100).round()}%',
              style: Studio.numeric(13, color: Studio.amber)),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 5,
                child: Stack(children: [
                  Container(color: Studio.line),
                  FractionallySizedBox(
                    widthFactor: pct.clamp(0.0, 1.0),
                    child: Container(color: Studio.amber),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackRow extends StatefulWidget {
  final Track track;
  final int index;
  final VoidCallback onOpen;
  const _TrackRow(
      {required this.track, required this.index, required this.onOpen});

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool _hover = false;

  void _menu() {
    final lib = context.read<LibraryStore>();
    final t = widget.track;
    showStudioMenu(context, title: t.title, actions: [
      StudioMenuAction('Rename', icon: Icons.edit_outlined, onTap: () async {
        final name =
            await studioPrompt(context, title: 'Rename Track', initial: t.title);
        if (name != null && name.trim().isNotEmpty) {
          t.title = name.trim();
          if (mounted) lib.updateTrack(t);
        }
      }),
      StudioMenuAction(t.done ? 'Mark as not done' : 'Mark as done',
          icon: Icons.check_circle_outline, onTap: () {
        t.done = !t.done;
        lib.updateTrack(t);
      }),
      StudioMenuAction('Delete',
          icon: Icons.delete_outline,
          destructive: true,
          onTap: () => lib.deleteTrack(t)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final lib = context.read<LibraryStore>();
    final audio = context.watch<AudioController>();
    final isCurrent = audio.current?.id == t.id;
    final isPlaying = isCurrent && audio.isPlaying;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isCurrent
                ? Studio.amberSoft
                : (_hover ? Studio.surfaceHigh : Studio.surface),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isCurrent ? Studio.amber : Studio.line,
                width: isCurrent ? 1.5 : 1),
          ),
          child: Row(
            children: [
              // done / play indicator
              GestureDetector(
                onTap: () {
                  t.done = !t.done;
                  lib.updateTrack(t);
                },
                child: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.done ? Studio.amber : Colors.transparent,
                    border: Border.all(
                        color: t.done ? Studio.amber : Studio.line, width: 1.5),
                  ),
                  child: Icon(
                    t.done ? Icons.check : Icons.play_arrow_rounded,
                    size: 17,
                    color: t.done ? Studio.bg : Studio.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 26,
                child: Text(
                    '${t.order > 0 ? t.order : widget.index + 1}'
                        .padLeft(2, '0'),
                    style: Studio.numeric(12, color: Studio.textDim)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Studio.body.copyWith(
                          color: t.done ? Studio.textSecondary : Studio.textPrimary,
                          decoration: t.done
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        )),
                    const SizedBox(height: 2),
                    Row(children: [
                      Text('${t.bpm} BPM',
                          style: Studio.numeric(11, color: Studio.textSecondary)),
                      Text('  ·  ${t.beatsPerBar}/4', style: Studio.bodyDim),
                      if (t.photoPaths.isNotEmpty)
                        Text('  ·  ${t.photoPaths.length} 📷',
                            style: Studio.bodyDim),
                    ]),
                  ],
                ),
              ),
              if (isPlaying) ...[
                const EqualizerBars(size: 16),
                const SizedBox(width: 8),
              ],
              StudioIconButton(
                  icon: Icons.more_horiz,
                  size: 20,
                  color: Studio.textSecondary,
                  onTap: _menu),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onImport;
  const _Empty({required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.queue_music_outlined,
              size: 64, color: Studio.textDim),
          const SizedBox(height: 16),
          const Text('No tracks yet', style: Studio.title),
          const SizedBox(height: 6),
          const Text('Import mp3 files to get started.', style: Studio.bodyDim),
          const SizedBox(height: 20),
          StudioButton(
              label: 'Import Audio',
              icon: Icons.library_add_outlined,
              onTap: onImport),
        ],
      ),
    );
  }
}
