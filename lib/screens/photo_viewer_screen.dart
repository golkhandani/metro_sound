import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/library_store.dart';
import '../ui/studio.dart';

/// Full-screen, zoomable, swipeable viewer for a track's practice photos.
/// Audio + metronome keep playing underneath (this is pushed over the player).
class PhotoViewerScreen extends StatefulWidget {
  final Track track;
  final int initialIndex;
  const PhotoViewerScreen(
      {super.key, required this.track, this.initialIndex = 0});

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

  Future<void> _add() async {
    final library = context.read<LibraryStore>();
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path != null) await library.addPhoto(widget.track, path);
    }
  }

  Future<void> _delete(List<String> photos) async {
    if (photos.isEmpty) return;
    final ok = await studioConfirm(context,
        title: 'Delete this photo?', confirmLabel: 'Delete', destructive: true);
    if (ok && mounted) {
      await context.read<LibraryStore>().removePhoto(widget.track, photos[_index]);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LibraryStore>();
    final photos = widget.track.photoPaths;

    return StudioScaffold(
      title: widget.track.title,
      subtitle: photos.isEmpty ? null : '${_index + 1} / ${photos.length}',
      showBack: true,
      actions: [
        StudioIconButton(
            icon: Icons.add_a_photo_outlined, tooltip: 'Add photo', onTap: _add),
        if (photos.isNotEmpty)
          StudioIconButton(
              icon: Icons.delete_outline,
              tooltip: 'Delete photo',
              onTap: () => _delete(photos)),
      ],
      body: photos.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.photo_library_outlined,
                      size: 64, color: Studio.textDim),
                  const SizedBox(height: 16),
                  const Text('No photos yet', style: Studio.bodyDim),
                  const SizedBox(height: 16),
                  StudioButton(
                      label: 'Add Photo',
                      icon: Icons.add_a_photo_outlined,
                      onTap: _add),
                ],
              ),
            )
          : PageView.builder(
              controller: _controller,
              itemCount: photos.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                    child: Image.file(File(photos[i]), fit: BoxFit.contain)),
              ),
            ),
    );
  }
}
