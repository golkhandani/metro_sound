import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/library_store.dart';

/// Full-screen, zoomable, swipeable viewer for a track's practice photos.
/// Audio + metronome keep playing underneath (this is pushed over the player).
class PhotoViewerScreen extends StatefulWidget {
  final Track track;
  final int initialIndex;
  const PhotoViewerScreen({
    super.key,
    required this.track,
    this.initialIndex = 0,
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    final library = context.read<LibraryStore>();
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path != null) await library.addPhoto(widget.track, path);
    }
  }

  Future<void> _deleteCurrent(List<String> photos) async {
    if (photos.isEmpty) return;
    final library = context.read<LibraryStore>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this photo?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await library.removePhoto(widget.track, photos[_index]);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LibraryStore>(); // rebuild when photos change
    final photos = widget.track.photoPaths;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(photos.isEmpty
            ? widget.track.title
            : '${widget.track.title}  ·  ${_index + 1}/${photos.length}'),
        actions: [
          IconButton(
            tooltip: 'Add photo',
            onPressed: _addPhoto,
            icon: const Icon(Icons.add_a_photo),
          ),
          if (photos.isNotEmpty)
            IconButton(
              tooltip: 'Delete photo',
              onPressed: () => _deleteCurrent(photos),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: photos.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.photo_library_outlined,
                      size: 72, color: Colors.white38),
                  const SizedBox(height: 16),
                  const Text('No photos yet',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _addPhoto,
                    icon: const Icon(Icons.add_a_photo),
                    label: const Text('Add photo'),
                  ),
                ],
              ),
            )
          : PageView.builder(
              controller: _controller,
              itemCount: photos.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: Image.file(File(photos[i]), fit: BoxFit.contain),
                  ),
                );
              },
            ),
    );
  }
}
