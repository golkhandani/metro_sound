import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/book.dart';
import '../models/track.dart';

/// Owns the books and their tracks, persisted to a JSON file in the app's
/// documents directory. Imported audio/photos are copied into app storage so
/// the library is self-contained.
class LibraryStore extends ChangeNotifier {
  final List<Book> _books = [];
  final List<Track> _tracks = [];

  List<Book> get books {
    final list = [..._books]..sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        return byOrder != 0 ? byOrder : a.title.compareTo(b.title);
      });
    return List.unmodifiable(list);
  }

  /// Tracks belonging to a given book, sorted by order then title.
  List<Track> tracksForBook(String bookId) {
    final list = _tracks.where((t) => t.bookId == bookId).toList()
      ..sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        return byOrder != 0 ? byOrder : a.title.compareTo(b.title);
      });
    return list;
  }

  int trackCount(String bookId) =>
      _tracks.where((t) => t.bookId == bookId).length;

  int doneCount(String bookId) =>
      _tracks.where((t) => t.bookId == bookId && t.done).length;

  // Exposed for the Drive sync service.
  List<Book> get allBooks => List.unmodifiable(_books);
  List<Track> get allTracks => List.unmodifiable(_tracks);
  String get audioDirPath => _audioDir.path;
  String get photoDirPath => _photoDir.path;
  String get coverDirPath => _coverDir.path;

  /// Replace the whole catalog (used when loading from Drive) and persist.
  Future<void> replaceCatalog(List<Book> books, List<Track> tracks) async {
    _books
      ..clear()
      ..addAll(books);
    _tracks
      ..clear()
      ..addAll(tracks);
    await save();
    notifyListeners();
  }

  late Directory _appDir;
  late Directory _audioDir;
  late Directory _photoDir;
  late Directory _coverDir;
  late File _dbFile;
  bool _ready = false;
  bool get ready => _ready;

  int _seq = 0;
  String _newId() {
    _seq++;
    return '${DateTime.now().microsecondsSinceEpoch}_$_seq';
  }

  Future<void> init() async {
    _appDir = await getApplicationSupportDirectory();
    _audioDir = Directory(p.join(_appDir.path, 'audio'));
    _photoDir = Directory(p.join(_appDir.path, 'photos'));
    _coverDir = Directory(p.join(_appDir.path, 'covers'));
    _dbFile = File(p.join(_appDir.path, 'library.json'));
    await _audioDir.create(recursive: true);
    await _photoDir.create(recursive: true);
    await _coverDir.create(recursive: true);
    await _load();
    _ready = true;
    notifyListeners();
  }

  Future<void> _load() async {
    if (!await _dbFile.exists()) return;
    try {
      final data = jsonDecode(await _dbFile.readAsString());
      final bookList = (data['books'] as List?) ?? [];
      final trackList = (data['tracks'] as List?) ?? [];
      _books
        ..clear()
        ..addAll(bookList.map((e) => Book.fromJson(e as Map<String, dynamic>)));
      _tracks
        ..clear()
        ..addAll(trackList.map((e) => Track.fromJson(e as Map<String, dynamic>)));
      _rehomePaths();
      await _migrateOrphans();
      await save(); // persist the corrected paths
    } catch (e) {
      debugPrint('LibraryStore load error: $e');
    }
  }

  /// iOS (and sandboxed macOS) move the app's data container on reinstall, so
  /// the absolute paths saved in library.json go stale. Rebuild each path from
  /// the *current* directory + the stored filename so files are found again.
  void _rehomePaths() {
    for (final t in _tracks) {
      t.audioPath = p.join(_audioDir.path, p.basename(t.audioPath));
      for (var i = 0; i < t.photoPaths.length; i++) {
        t.photoPaths[i] = p.join(_photoDir.path, p.basename(t.photoPaths[i]));
      }
    }
    for (final b in _books) {
      final c = b.coverPath;
      if (c != null) b.coverPath = p.join(_coverDir.path, p.basename(c));
    }
  }

  /// Older versions stored a flat track list with no books. Put any track that
  /// has no (or an unknown) book into a default book so nothing is lost.
  Future<void> _migrateOrphans() async {
    final knownIds = _books.map((b) => b.id).toSet();
    final orphans =
        _tracks.where((t) => t.bookId.isEmpty || !knownIds.contains(t.bookId));
    if (orphans.isEmpty) return;
    final defaultBook = Book(
      id: _newId(),
      title: 'My Practice',
      order: 0,
    );
    _books.add(defaultBook);
    for (final t in orphans) {
      t.bookId = defaultBook.id;
    }
    await save();
  }

  Future<void> save() async {
    final data = {
      'books': _books.map((b) => b.toJson()).toList(),
      'tracks': _tracks.map((t) => t.toJson()).toList(),
    };
    await _dbFile.writeAsString(jsonEncode(data));
  }

  // ─── Books ───

  Future<Book> createBook(String title) async {
    final book = Book(
      id: _newId(),
      title: title.trim().isEmpty ? 'Untitled book' : title.trim(),
      order: _books.length,
    );
    _books.add(book);
    await save();
    notifyListeners();
    return book;
  }

  Future<void> renameBook(Book book, String title) async {
    if (title.trim().isEmpty) return;
    book.title = title.trim();
    await save();
    notifyListeners();
  }

  /// Copy a picked image into app storage and set it as the book's cover.
  Future<void> setBookCover(Book book, String sourcePath) async {
    try {
      // Remove any previous cover file first.
      await _removeCoverFile(book);
      final ext = p.extension(sourcePath);
      // Unique name so a replaced cover isn't served stale from the image cache.
      final dest = p.join(_coverDir.path, '${book.id}_${_newId()}$ext');
      await File(sourcePath).copy(dest);
      book.coverPath = dest;
      await save();
      notifyListeners();
    } catch (e) {
      debugPrint('setBookCover error: $e');
    }
  }

  Future<void> removeBookCover(Book book) async {
    await _removeCoverFile(book);
    book.coverPath = null;
    await save();
    notifyListeners();
  }

  Future<void> _removeCoverFile(Book book) async {
    final path = book.coverPath;
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> deleteBook(Book book) async {
    await _removeCoverFile(book);
    for (final t in tracksForBook(book.id)) {
      await _deleteTrackFiles(t);
      _tracks.remove(t);
    }
    _books.removeWhere((b) => b.id == book.id);
    await save();
    notifyListeners();
  }

  // ─── Tracks ───

  /// Copy picked audio files into app storage and create Track rows in [bookId].
  /// Returns the number of tracks added.
  Future<int> importAudioFiles(String bookId, List<String> sourcePaths) async {
    int added = 0;
    final existing = trackCount(bookId);
    for (final src in sourcePaths) {
      try {
        final ext = p.extension(src);
        final id = _newId();
        final dest = p.join(_audioDir.path, '$id$ext');
        await File(src).copy(dest);
        final (order, title) = Track.parseFileName(src);
        _tracks.add(Track(
          id: id,
          bookId: bookId,
          title: title,
          order: order == 0 ? existing + added + 1 : order,
          audioPath: dest,
        ));
        added++;
      } catch (e) {
        debugPrint('Import failed for $src: $e');
      }
    }
    if (added > 0) {
      await save();
      notifyListeners();
    }
    return added;
  }

  Future<void> updateTrack(Track t) async {
    await save();
    notifyListeners();
  }

  Future<void> deleteTrack(Track t) async {
    _tracks.removeWhere((x) => x.id == t.id);
    await _deleteTrackFiles(t);
    await save();
    notifyListeners();
  }

  Future<void> _deleteTrackFiles(Track t) async {
    try {
      final f = File(t.audioPath);
      if (await f.exists()) await f.delete();
      for (final ph in t.photoPaths) {
        final pf = File(ph);
        if (await pf.exists()) await pf.delete();
      }
    } catch (e) {
      debugPrint('Delete cleanup error: $e');
    }
  }

  /// Copy a picked photo into app storage and attach it to the track.
  Future<void> addPhoto(Track t, String sourcePath) async {
    final ext = p.extension(sourcePath);
    final dest = p.join(_photoDir.path, '${_newId()}$ext');
    await File(sourcePath).copy(dest);
    t.photoPaths.add(dest);
    await save();
    notifyListeners();
  }

  Future<void> removePhoto(Track t, String photoPath) async {
    t.photoPaths.remove(photoPath);
    try {
      final f = File(photoPath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await save();
    notifyListeners();
  }
}
