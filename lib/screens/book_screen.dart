import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/book.dart';
import '../models/track.dart';
import '../services/audio_controller.dart';
import '../services/library_store.dart';
import '../services/package_service.dart';
import '../services/recorder.dart';
import '../ui/studio.dart';
import '../widgets/package_progress_sheet.dart';
import 'player_screen.dart';
import 'record_screen.dart';

class BookScreen extends StatelessWidget {
  final Book book;
  const BookScreen({super.key, required this.book});

  /// Export this book in the background and show the progress sheet.
  Future<void> _share(BuildContext context) async {
    final library = context.read<LibraryStore>();
    if (library.tracksForBook(book.id).isEmpty) {
      showToast(context, 'Add some tracks before sharing');
      return;
    }
    final packages = context.read<PackageService>();
    if (!await packages.startExportBooks([book])) {
      if (context.mounted) {
        showToast(context, 'Another export is already running');
      }
      return;
    }
    if (context.mounted) await showPackageProgressSheet(context);
  }

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

  void _record(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            RecordScreen(bookId: book.id, bookTitle: book.title)));
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
        if (Recorder.supported)
          StudioIconButton(
              icon: Icons.mic_none,
              tooltip: 'Record a track',
              onTap: () => _record(context)),
        StudioIconButton(
            icon: Icons.ios_share,
            tooltip: 'Share book',
            onTap: () => _share(context)),
        StudioIconButton(
            icon: Icons.add,
            tooltip: 'Import audio',
            onTap: () => _import(context)),
      ],
      body: tracks.isEmpty
          ? _Empty(
              onImport: () => _import(context),
              onRecord:
                  Recorder.supported ? () => _record(context) : null)
          : Column(
              children: [
                _ProgressBar(done: done, total: tracks.length),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    buildDefaultDragHandles: false,
                    itemCount: tracks.length,
                    onReorderItem: (oldIndex, newIndex) => library
                        .reorderTracks(book.id, oldIndex, newIndex),
                    proxyDecorator: (child, index, anim) => Material(
                      color: Colors.transparent,
                      child: child,
                    ),
                    itemBuilder: (context, i) => _TrackRow(
                      key: ValueKey(tracks[i].id),
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
      {super.key,
      required this.track,
      required this.index,
      required this.onOpen});

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
      StudioMenuAction('Share track', icon: Icons.ios_share, onTap: () async {
        // Package: audio + settings + photos, importable by Metro Sound users.
        final parent = lib.books.where((b) => b.id == t.bookId).firstOrNull;
        if (parent == null) return;
        final packages = context.read<PackageService>();
        if (!await packages.startExportTrack(parent, t)) {
          if (mounted) {
            showToast(context, 'Another export is already running');
          }
          return;
        }
        if (mounted) await showPackageProgressSheet(context);
      }),
      StudioMenuAction('Share audio file',
          icon: Icons.audiotrack_outlined, onTap: () async {
        // Raw audio for any app — instant, no packaging job.
        try {
          await Share.shareXFiles(
            [XFile(t.audioPath)],
            subject: t.title,
            // The menu has already popped; use the safe fallback anchor.
            sharePositionOrigin: const Rect.fromLTWH(0, 0, 100, 100),
          );
        } catch (e) {
          if (mounted) showToast(context, 'Share failed: $e');
        }
      }),
      StudioMenuAction('Delete',
          icon: Icons.delete_outline,
          destructive: true, onTap: () async {
        final ok = await studioConfirm(context,
            title: 'Delete "${t.title}"?',
            message: 'This removes the track and its audio from this device.',
            confirmLabel: 'Delete',
            destructive: true);
        if (ok) lib.deleteTrack(t);
      }),
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
        onTap: () {
          Haptics.impact();
          widget.onOpen();
        },
        onLongPress: () {
          Haptics.impact();
          _menu();
        },
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
              // Done checkbox (hollow ring → filled amber check). Tapping the
              // row plays; tapping this marks the lesson done.
              Pressable(
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
                  child: t.done
                      ? const Icon(Icons.check, size: 17, color: Studio.bg)
                      : null,
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
                      Text('  ·  ${t.beatsPerBar}/${t.timeSigDenominator}',
                          style: Studio.bodyDim),
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
              // Drag handle — only this grabs to reorder, so tapping the row
              // still opens the player.
              ReorderableDragStartListener(
                index: widget.index,
                child: const MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: Icon(Icons.drag_handle,
                        size: 20, color: Studio.textDim),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onImport;
  final VoidCallback? onRecord;
  const _Empty({required this.onImport, this.onRecord});

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
          const Text('Import mp3 files or record a new one to get started.',
              style: Studio.bodyDim),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StudioButton(
                  label: 'Import Audio',
                  icon: Icons.library_add_outlined,
                  onTap: onImport),
              if (onRecord != null) ...[
                const SizedBox(width: 10),
                StudioButton(
                    label: 'Record',
                    icon: Icons.mic_none,
                    kind: StudioButtonKind.ghost,
                    onTap: onRecord),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
