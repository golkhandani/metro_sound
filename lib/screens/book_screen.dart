import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../models/track.dart';
import '../services/audio_controller.dart';
import '../services/library_store.dart';
import 'player_screen.dart';

/// Shows the tracks (songs) inside a single book.
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
    final paths = result.files
        .map((f) => f.path)
        .whereType<String>()
        .toList(growable: false);
    final added = await library.importAudioFiles(book.id, paths);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $added track(s)')),
      );
    }
  }

  void _openPlayer(BuildContext context, List<Track> tracks, int index) {
    final audio = context.read<AudioController>();
    audio.openQueue(tracks, index);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final tracks = library.tracksForBook(book.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(book.title),
        actions: [
          IconButton(
            tooltip: 'Import audio',
            onPressed: () => _import(context),
            icon: const Icon(Icons.library_add),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _import(context),
        icon: const Icon(Icons.add),
        label: const Text('Import audio'),
      ),
      body: tracks.isEmpty
          ? _EmptyState(onImport: () => _import(context))
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: tracks.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final t = tracks[i];
                return _TrackTile(
                  track: t,
                  onTap: () => _openPlayer(context, tracks, i),
                );
              },
            ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  const _TrackTile({required this.track, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: track.done ? cs.primary : cs.primaryContainer,
        child: track.done
            ? Icon(Icons.check, color: cs.onPrimary)
            : Text(
                track.order > 0 ? '${track.order}' : '•',
                style: TextStyle(color: cs.onPrimaryContainer),
              ),
      ),
      title: Text(
        track.title,
        style: track.done
            ? TextStyle(color: cs.outline, decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Row(
        children: [
          Icon(Icons.music_note, size: 14, color: cs.outline),
          const SizedBox(width: 4),
          Text('${track.bpm} BPM · ${track.beatsPerBar}/4',
              style: Theme.of(context).textTheme.bodySmall),
          if (track.photoPaths.isNotEmpty) ...[
            const SizedBox(width: 10),
            Icon(Icons.photo, size: 14, color: cs.outline),
            const SizedBox(width: 4),
            Text('${track.photoPaths.length}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: track.done ? 'Mark as not done' : 'Mark lesson as done',
            child: Checkbox(
              value: track.done,
              onChanged: (v) {
                track.done = v ?? false;
                context.read<LibraryStore>().updateTrack(track);
              },
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') {
                context.read<LibraryStore>().deleteTrack(track);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onImport;
  const _EmptyState({required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.queue_music,
              size: 72, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text('No tracks in this book yet',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('Import your mp3 files to get started.'),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.library_add),
            label: const Text('Import audio'),
          ),
        ],
      ),
    );
  }
}
