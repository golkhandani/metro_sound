import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../services/library_store.dart';
import '../ui/studio.dart';
import 'book_screen.dart';

class BooksScreen extends StatelessWidget {
  const BooksScreen({super.key});

  Future<void> _createBook(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final title = await studioPrompt(context,
        title: 'New Book', hint: 'e.g. Ketab-e Aval — Tār');
    if (title == null || title.trim().isEmpty) return;
    final book = await library.createBook(title);
    if (context.mounted) {
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => BookScreen(book: book)));
    }
  }

  Future<void> _setCover(BuildContext context, Book book) async {
    final library = context.read<LibraryStore>();
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path =
        (result != null && result.files.isNotEmpty) ? result.files.first.path : null;
    if (path != null) await library.setBookCover(book, path);
  }

  void _menu(BuildContext context, Book book) {
    final library = context.read<LibraryStore>();
    final hasCover =
        book.coverPath != null && File(book.coverPath!).existsSync();
    showStudioMenu(context, title: book.title, actions: [
      StudioMenuAction('Rename',
          icon: Icons.edit_outlined, onTap: () async {
        final t = await studioPrompt(context,
            title: 'Rename Book', initial: book.title);
        if (t != null) await library.renameBook(book, t);
      }),
      StudioMenuAction(hasCover ? 'Change cover' : 'Add cover',
          icon: Icons.image_outlined, onTap: () => _setCover(context, book)),
      if (hasCover)
        StudioMenuAction('Remove cover',
            icon: Icons.hide_image_outlined,
            onTap: () => library.removeBookCover(book)),
      StudioMenuAction('Delete',
          icon: Icons.delete_outline,
          destructive: true, onTap: () async {
        final n = library.trackCount(book.id);
        final ok = await studioConfirm(context,
            title: 'Delete "${book.title}"?',
            message: n == 0 ? 'This book is empty.' : 'Deletes $n track(s).',
            confirmLabel: 'Delete',
            destructive: true);
        if (ok) await library.deleteBook(book);
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final books = library.books;

    return StudioScaffold(
      title: 'Metro Sound',
      subtitle: 'Practice Library',
      actions: [
        StudioIconButton(
            icon: Icons.add,
            tooltip: 'New book',
            onTap: () => _createBook(context)),
      ],
      body: !library.ready
          ? const Center(
              child: CircularProgressIndicator(color: Studio.amber))
          : books.isEmpty
              ? _Empty(onCreate: () => _createBook(context))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.6,
                  ),
                  itemCount: books.length,
                  itemBuilder: (context, i) {
                    final book = books[i];
                    return _BookTile(
                      book: book,
                      total: library.trackCount(book.id),
                      done: library.doneCount(book.id),
                      onOpen: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => BookScreen(book: book))),
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
    required this.book,
    required this.total,
    required this.done,
    required this.onOpen,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final hasCover = book.coverPath != null && File(book.coverPath!).existsSync();
    return Pressable(
      onTap: onOpen,
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
                      Container(
                        color: Studio.surfaceHigh,
                        child: const Center(
                          child: Icon(Icons.album_outlined,
                              size: 44, color: Studio.textDim),
                        ),
                      ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: StudioIconButton(
                          icon: Icons.more_horiz,
                          size: 18,
                          color: Studio.textPrimary,
                          onTap: onMenu),
                    ),
                    if (total > 0)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Studio.bg.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Studio.line),
                          ),
                          child: Text('$done/$total',
                              style: Studio.numeric(11, color: Studio.amber)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Studio.title.copyWith(fontSize: 13)),
            Text(total == 0 ? 'Empty' : '$total tracks', style: Studio.bodyDim),
          ],
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
          const Icon(Icons.library_music_outlined,
              size: 64, color: Studio.textDim),
          const SizedBox(height: 16),
          const Text('No books yet', style: Studio.title),
          const SizedBox(height: 6),
          const Text('Create a book, then import its practice tracks.',
              style: Studio.bodyDim),
          const SizedBox(height: 20),
          StudioButton(
              label: 'New Book', icon: Icons.add, onTap: onCreate),
        ],
      ),
    );
  }
}
