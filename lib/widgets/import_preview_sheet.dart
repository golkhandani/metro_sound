import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../services/library_store.dart';
import '../services/package_service.dart';
import '../ui/studio.dart';
import 'package_progress_sheet.dart';

/// The full import flow: pick a `.metrosound` file → preview (choose books/
/// tracks, append-vs-copy) → background import with the progress sheet.
/// Reused by Settings and the library screen.
Future<void> runPackageImportFlow(BuildContext context) async {
  final packages = context.read<PackageService>();
  final result = await FilePicker.platform.pickFiles(type: FileType.any);
  final path = result?.files.single.path;
  if (path == null || !context.mounted) return;

  final PackagePreview preview;
  try {
    preview = await packages.readPreview(path);
  } catch (_) {
    if (context.mounted) {
      showToast(context, "That file isn't a Metro Sound library");
    }
    return;
  }
  if (!context.mounted) return;

  final selection = await showImportPreviewSheet(context, preview);
  if (selection == null || !context.mounted) return;
  if (!await packages.startImport(preview, selection)) {
    if (context.mounted) {
      showToast(context, 'Another export is already running');
    }
    return;
  }
  if (context.mounted) await showPackageProgressSheet(context);
}

/// Preview of a shared package: pick which books and individual tracks to
/// import. Returns the selection, or null if cancelled.
Future<ImportSelection?> showImportPreviewSheet(
  BuildContext context,
  PackagePreview preview,
) {
  return showModalBottomSheet<ImportSelection>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ImportPreviewSheet(preview: preview),
  );
}

class _ImportPreviewSheet extends StatefulWidget {
  final PackagePreview preview;
  const _ImportPreviewSheet({required this.preview});

  @override
  State<_ImportPreviewSheet> createState() => _ImportPreviewSheetState();
}

class _ImportPreviewSheetState extends State<_ImportPreviewSheet> {
  // Selected manifest track ids, plus books explicitly kept (covers the
  // empty-book case and books whose tracks are partially selected).
  final Set<String> _tracks = {};
  final Set<String> _books = {};
  final Set<String> _expanded = {};

  // pkg book id -> matching local book (already in the library), if any.
  final Map<String, Book> _matches = {};
  // pkg book id -> true = append into the match, false = import as new copy.
  final Map<String, bool> _append = {};

  @override
  void initState() {
    super.initState();
    final library = context.read<LibraryStore>();
    // Everything selected by default — import-all stays one tap.
    for (final b in widget.preview.books) {
      final id = b['id'] as String;
      _books.add(id);
      final match = library.findMatchingBook(b);
      if (match != null) {
        _matches[id] = match;
        _append[id] = true; // append is the safe default: no duplicates
      }
    }
    for (final t in widget.preview.tracks) {
      _tracks.add(t['id'] as String);
    }
  }

  int get _selectedBytes => widget.preview.tracks
      .where((t) => _tracks.contains(t['id']))
      .fold(0, (s, t) => s + widget.preview.trackSize(t));

  void _toggleBook(String bookId, List<Map<String, dynamic>> tracks) {
    setState(() {
      final ids = tracks.map((t) => t['id'] as String);
      final allOn = _books.contains(bookId) && ids.every(_tracks.contains);
      if (allOn) {
        _books.remove(bookId);
        _tracks.removeAll(ids);
      } else {
        _books.add(bookId);
        _tracks.addAll(ids);
      }
    });
  }

  void _toggleTrack(String bookId, String trackId) {
    setState(() {
      if (_tracks.contains(trackId)) {
        _tracks.remove(trackId);
      } else {
        _tracks.add(trackId);
        _books.add(bookId); // a selected track always brings its book
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final selectedTracks = _tracks.length;
    // A book imports if explicitly checked or if any of its tracks are.
    final effectiveBooks = <String>{
      for (final b in preview.books)
        if (_books.contains(b['id']) ||
            preview
                .tracksForBook(b['id'] as String)
                .any((t) => _tracks.contains(t['id'])))
          b['id'] as String,
    };

    return Container(
      margin: const EdgeInsets.all(10),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: Studio.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Studio.line),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    color: Studio.amber,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Import package', style: Studio.title),
                        const SizedBox(height: 2),
                        Text(
                          preview.fileName,
                          style: Studio.bodyDim,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: Studio.line, height: 16),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [for (final b in preview.books) ..._bookRows(b)],
              ),
            ),
            Divider(color: Studio.line, height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      selectedTracks == 0
                          ? 'Nothing selected'
                          : '$selectedTracks tracks · ${formatBytes(_selectedBytes)}',
                      style: Studio.bodyDim,
                    ),
                  ),
                  StudioButton(
                    label: 'Cancel',
                    kind: StudioButtonKind.ghost,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  StudioButton(
                    label: 'Import',
                    icon: Icons.download_outlined,
                    onTap: effectiveBooks.isEmpty
                        ? null
                        : () {
                            final targets = <String, String?>{
                              for (final id in effectiveBooks)
                                id: (_append[id] ?? false)
                                    ? _matches[id]?.id
                                    : null,
                            };
                            Navigator.of(context).pop(
                              ImportSelection(
                                effectiveBooks,
                                Set.of(_tracks),
                                bookTargets: targets,
                              ),
                            );
                          },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _bookRows(Map<String, dynamic> b) {
    final bookId = b['id'] as String;
    final tracks = widget.preview.tracksForBook(bookId);
    final selectedInBook = tracks
        .where((t) => _tracks.contains(t['id']))
        .length;
    final allOn =
        _books.contains(bookId) &&
        (tracks.isEmpty || selectedInBook == tracks.length);
    final someOn = selectedInBook > 0 && !allOn;
    final expanded = _expanded.contains(bookId);
    final match = _matches[bookId];

    return [
      Pressable(
        onTap: () => _toggleBook(bookId, tracks),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _check(allOn, someOn),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (b['title'] as String?) ?? 'Book',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Studio.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (match != null) ...[
                      const SizedBox(height: 4),
                      _mergeChoice(bookId, match),
                    ],
                  ],
                ),
              ),
              Text('${tracks.length} tracks', style: Studio.bodyDim),
              if (tracks.isNotEmpty)
                StudioIconButton(
                  icon: expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  onTap: () => setState(() {
                    expanded ? _expanded.remove(bookId) : _expanded.add(bookId);
                  }),
                ),
            ],
          ),
        ),
      ),
      if (expanded)
        for (final t in tracks)
          Pressable(
            onTap: () => _toggleTrack(bookId, t['id'] as String),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(40, 6, 16, 6),
              child: Row(
                children: [
                  _check(_tracks.contains(t['id']), false),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      (t['title'] as String?) ?? 'Track',
                      style: Studio.body,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    formatBytes(widget.preview.trackSize(t)),
                    style: Studio.bodyDim,
                  ),
                ],
              ),
            ),
          ),
    ];
  }

  /// "Already in your library" badge + a tap-to-flip Append / New-copy choice.
  Widget _mergeChoice(String bookId, Book match) {
    final append = _append[bookId] ?? false;
    return GestureDetector(
      onTap: () => setState(() => _append[bookId] = !append),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: append ? Studio.amberSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: append ? Studio.amber : Studio.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              append ? Icons.merge : Icons.copy_all,
              size: 12,
              color: append ? Studio.amber : Studio.textSecondary,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                append
                    ? 'Add new tracks to your "${match.title}"'
                    : 'Import as a separate copy',
                style: TextStyle(
                  fontSize: 11,
                  color: append ? Studio.amber : Studio.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _check(bool on, bool partial) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: on || partial ? Studio.amberSoft : Colors.transparent,
      border: Border.all(
        color: on || partial ? Studio.amber : Studio.line,
        width: 1.5,
      ),
    ),
    child: on
        ? Icon(Icons.check, size: 14, color: Studio.amber)
        : partial
        ? Icon(Icons.remove, size: 14, color: Studio.amber)
        : null,
  );
}
