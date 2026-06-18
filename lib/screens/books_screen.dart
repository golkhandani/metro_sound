import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../services/library_store.dart';
import 'book_screen.dart';
import 'settings_screen.dart';

/// Home screen: a folder-style list of books. Tap a book to see its tracks.
class BooksScreen extends StatelessWidget {
  const BooksScreen({super.key});

  Future<void> _createBook(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final title = await _promptForName(context, title: 'New book');
    if (title == null) return;
    final book = await library.createBook(title);
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BookScreen(book: book)),
      );
    }
  }

  Future<void> _renameBook(BuildContext context, Book book) async {
    final library = context.read<LibraryStore>();
    final title =
        await _promptForName(context, title: 'Rename book', initial: book.title);
    if (title != null) await library.renameBook(book, title);
  }

  Future<void> _setCover(BuildContext context, Book book) async {
    final library = context.read<LibraryStore>();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );
    final path =
        (result != null && result.files.isNotEmpty) ? result.files.first.path : null;
    if (path != null) await library.setBookCover(book, path);
  }

  Future<void> _confirmDelete(BuildContext context, Book book) async {
    final library = context.read<LibraryStore>();
    final count = library.trackCount(book.id);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${book.title}"?'),
        content: Text(count == 0
            ? 'This book is empty.'
            : 'This will delete the book and its $count track(s).'),
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
    if (ok == true) await library.deleteBook(book);
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final books = library.books;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice Books'),
        actions: [
          IconButton(
            tooltip: 'Settings & Drive sync',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createBook(context),
        icon: const Icon(Icons.create_new_folder),
        label: const Text('New book'),
      ),
      body: !library.ready
          ? const Center(child: CircularProgressIndicator())
          : books.isEmpty
              ? _EmptyState(onCreate: () => _createBook(context))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 18,
                    crossAxisSpacing: 18,
                    // Portrait, book-cover proportions (cover ~2:3 plus the
                    // title/count strip below).
                    childAspectRatio: 0.56,
                  ),
                  itemCount: books.length,
                  itemBuilder: (context, i) {
                    final book = books[i];
                    return _BookCard(
                      book: book,
                      total: library.trackCount(book.id),
                      done: library.doneCount(book.id),
                      onOpen: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => BookScreen(book: book)),
                      ),
                      onRename: () => _renameBook(context, book),
                      onSetCover: () => _setCover(context, book),
                      onRemoveCover: () =>
                          context.read<LibraryStore>().removeBookCover(book),
                      onDelete: () => _confirmDelete(context, book),
                    );
                  },
                ),
    );
  }
}

class _BookCard extends StatelessWidget {
  final Book book;
  final int total;
  final int done;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onSetCover;
  final VoidCallback onRemoveCover;
  final VoidCallback onDelete;

  const _BookCard({
    required this.book,
    required this.total,
    required this.done,
    required this.onOpen,
    required this.onRename,
    required this.onSetCover,
    required this.onRemoveCover,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasCover = book.coverPath != null && File(book.coverPath!).existsSync();

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cover area
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasCover)
                    Image.file(File(book.coverPath!), fit: BoxFit.cover)
                  else
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [cs.primaryContainer, cs.secondaryContainer],
                        ),
                      ),
                      child: Icon(Icons.library_music,
                          size: 56,
                          color: cs.onPrimaryContainer.withValues(alpha: 0.7)),
                    ),
                  // Menu button, top-right
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.35),
                      shape: const CircleBorder(),
                      child: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert,
                            color: Colors.white, size: 20),
                        onSelected: (v) {
                          switch (v) {
                            case 'rename':
                              onRename();
                            case 'cover':
                              onSetCover();
                            case 'removeCover':
                              onRemoveCover();
                            case 'delete':
                              onDelete();
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'rename', child: Text('Rename')),
                          PopupMenuItem(
                              value: 'cover',
                              child: Text(hasCover
                                  ? 'Change cover photo'
                                  : 'Add cover photo')),
                          if (hasCover)
                            const PopupMenuItem(
                                value: 'removeCover',
                                child: Text('Remove cover')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                  ),
                  // Progress badge, bottom-left
                  if (total > 0)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$done / $total done',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Title + count
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    total == 0 ? 'Empty' : '$total track(s)',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _promptForName(BuildContext context,
    {required String title, String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'e.g. Ketab-e Aval — Tār',
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save')),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open,
              size: 72, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text('No books yet',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('Create a book, then import its practice tracks.'),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.create_new_folder),
            label: const Text('New book'),
          ),
        ],
      ),
    );
  }
}
