import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../services/library_store.dart';
import '../services/package_service.dart';
import '../ui/studio.dart';
import '../widgets/coach_marks.dart';
import '../widgets/import_preview_sheet.dart';
import '../widgets/package_progress_sheet.dart';
import 'book_screen.dart';

class BooksScreen extends StatelessWidget {
  const BooksScreen({super.key});

  Future<void> _createBook(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final title = await studioPrompt(
      context,
      title: 'New Book',
      hint: 'e.g. Ketab-e Aval — Tār',
    );
    if (title == null || title.trim().isEmpty) return;
    final book = await library.createBook(title);
    if (context.mounted) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => BookScreen(book: book)));
    }
  }

  Future<void> _setCover(BuildContext context, Book book) async {
    final library = context.read<LibraryStore>();
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = (result != null && result.files.isNotEmpty)
        ? result.files.first.path
        : null;
    if (path != null) await library.setBookCover(book, path);
  }

  void _menu(BuildContext context, Book book) {
    final library = context.read<LibraryStore>();
    final hasCover =
        book.coverPath != null && File(book.coverPath!).existsSync();
    showStudioMenu(
      context,
      title: book.title,
      actions: [
        StudioMenuAction(
          'Rename',
          icon: Icons.edit_outlined,
          onTap: () async {
            final t = await studioPrompt(
              context,
              title: 'Rename Book',
              initial: book.title,
            );
            if (t != null) await library.renameBook(book, t);
          },
        ),
        StudioMenuAction(
          hasCover ? 'Change cover' : 'Add cover',
          icon: Icons.image_outlined,
          onTap: () => _setCover(context, book),
        ),
        StudioMenuAction(
          'Share book',
          icon: Icons.ios_share,
          onTap: () async {
            if (library.trackCount(book.id) == 0) {
              showToast(context, 'This book has no tracks to share');
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
          },
        ),
        if (hasCover)
          StudioMenuAction(
            'Remove cover',
            icon: Icons.hide_image_outlined,
            onTap: () => library.removeBookCover(book),
          ),
        StudioMenuAction(
          'Delete',
          icon: Icons.delete_outline,
          destructive: true,
          onTap: () async {
            final n = library.trackCount(book.id);
            final ok = await studioConfirm(
              context,
              title: 'Delete "${book.title}"?',
              message: n == 0 ? 'This book is empty.' : 'Deletes $n track(s).',
              confirmLabel: 'Delete',
              destructive: true,
            );
            if (ok) await library.deleteBook(book);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final books = library.books;

    return StudioScaffold(
      title: 'Metro Sound',
      subtitle: 'Practice Library',
      actions: [
        KeyedSubtree(
          key: CoachKeys.booksImport,
          child: StudioIconButton(
            icon: Icons.download_outlined,
            tooltip: 'Import shared library',
            onTap: () => runPackageImportFlow(context),
          ),
        ),
        KeyedSubtree(
          key: CoachKeys.booksNewBook,
          child: StudioIconButton(
            icon: Icons.add,
            tooltip: 'New book',
            onTap: () => _createBook(context),
          ),
        ),
      ],
      body: !library.ready
          ? Center(child: CircularProgressIndicator(color: Studio.amber))
          : books.isEmpty
          ? _Empty(onCreate: () => _createBook(context))
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.6,
              ),
              itemCount: books.length,
              itemBuilder: (context, i) {
                final book = books[i];
                return _BookTile(
                  key: i == 0 ? CoachKeys.booksFirstTile : null,
                  book: book,
                  total: library.trackCount(book.id),
                  done: library.doneCount(book.id),
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => BookScreen(book: book)),
                  ),
                  onMenu: () => _menu(context, book),
                );
              },
            ),
    );
  }
}

class _BookTile extends StatelessWidget {
  final Book book;
  final int total;
  final int done;
  final VoidCallback onOpen;
  final VoidCallback onMenu;
  const _BookTile({
    super.key,
    required this.book,
    required this.total,
    required this.done,
    required this.onOpen,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final hasCover =
        book.coverPath != null && File(book.coverPath!).existsSync();
    return Pressable(
      onTap: onOpen,
      onLongPress: onMenu,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Studio.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasCover)
                      Image.file(File(book.coverPath!), fit: BoxFit.cover)
                    else
                      _ColorPlaceholder(seed: book.title),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: StudioIconButton(
                        icon: Icons.more_horiz,
                        size: 18,
                        color: Studio.textPrimary,
                        onTap: onMenu,
                      ),
                    ),
                    if (total > 0)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Studio.bg.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Studio.line),
                          ),
                          child: Text(
                            '$done/$total',
                            style: Studio.numeric(11, color: Studio.amber),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Studio.title.copyWith(fontSize: 13),
            ),
            Text(total == 0 ? 'Empty' : '$total tracks', style: Studio.bodyDim),
          ],
        ),
      ),
    );
  }
}

/// Colorful placeholder cover (hue derived from the title) so an empty library
/// isn't all grey.
class _ColorPlaceholder extends StatelessWidget {
  final String seed;
  const _ColorPlaceholder({required this.seed});

  @override
  Widget build(BuildContext context) {
    final h = seed.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff);
    final hue = (h % 360).toDouble();
    final c1 = HSLColor.fromAHSL(1, hue, 0.45, 0.40).toColor();
    final c2 = HSLColor.fromAHSL(1, (hue + 28) % 360, 0.50, 0.22).toColor();
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c1, c2],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.album_outlined,
          size: 44,
          color: Colors.white.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onCreate;
  const _Empty({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.library_music_outlined, size: 64, color: Studio.textDim),
          const SizedBox(height: 16),
          Text('No books yet', style: Studio.title),
          const SizedBox(height: 6),
          Text(
            'Create a book, then import its practice tracks.',
            style: Studio.bodyDim,
          ),
          const SizedBox(height: 20),
          StudioButton(label: 'New Book', icon: Icons.add, onTap: onCreate),
        ],
      ),
    );
  }
}
