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

  // Deletion tombstones (entity id -> epoch-ms deleted). Kept so two-way Drive
  // sync can propagate deletions instead of resurrecting them from a peer.
  final Map<String, int> _deleted = {};

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;

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
  Map<String, int> get tombstones => Map.unmodifiable(_deleted);
  String get audioDirPath => _audioDir.path;
  String get photoDirPath => _photoDir.path;
  String get coverDirPath => _coverDir.path;

  /// Stable fingerprint of the catalog's sync-relevant state (entity ids +
  /// their updatedAt + tombstones). Two devices that have fully converged
  /// produce the same signature, which the sync engine uses to stop looping.
  int catalogSignature() {
    final parts = <String>[];
    for (final b in [..._books]..sort((a, b) => a.id.compareTo(b.id))) {
      parts.add('b:${b.id}:${b.updatedAt}');
    }
    for (final t in [..._tracks]..sort((a, b) => a.id.compareTo(b.id))) {
      parts.add('t:${t.id}:${t.updatedAt}');
    }
    for (final id in _deleted.keys.toList()..sort()) {
      parts.add('d:$id:${_deleted[id]}');
    }
    // FNV-1a — stable across runs (unlike String.hashCode).
    var h = 0x811c9dc5;
    for (final c in parts.join('|').codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h;
  }

  /// Merge a remote catalog into the local one with last-write-wins per entity.
  /// [remoteBooks]/[remoteTracks] must already have their media downloaded and
  /// their paths point at local files (the sync service does this first).
  /// Returns true if anything changed locally.
  Future<bool> mergeRemote(List<Book> remoteBooks, List<Track> remoteTracks,
      Map<String, int> remoteDeleted) async {
    var changed = false;

    // Union tombstones (newest wins).
    remoteDeleted.forEach((id, ts) {
      if (ts > (_deleted[id] ?? 0)) {
        _deleted[id] = ts;
        changed = true;
      }
    });

    final bookById = {for (final b in _books) b.id: b};
    for (final rb in remoteBooks) {
      if ((_deleted[rb.id] ?? 0) >= rb.updatedAt) continue; // deleted later
      final lb = bookById[rb.id];
      if (lb == null) {
        _books.add(rb);
        changed = true;
      } else if (rb.updatedAt > lb.updatedAt) {
        lb
          ..title = rb.title
          ..order = rb.order
          ..coverPath = rb.coverPath
          ..updatedAt = rb.updatedAt;
        changed = true;
      }
    }

    final trackById = {for (final t in _tracks) t.id: t};
    for (final rt in remoteTracks) {
      if ((_deleted[rt.id] ?? 0) >= rt.updatedAt) continue;
      final lt = trackById[rt.id];
      if (lt == null) {
        _tracks.add(rt);
        changed = true;
      } else if (rt.updatedAt > lt.updatedAt) {
        lt
          ..bookId = rt.bookId
          ..title = rt.title
          ..order = rt.order
          ..audioPath = rt.audioPath
          ..bpm = rt.bpm
          ..beatsPerBar = rt.beatsPerBar
          ..timeSigDenominator = rt.timeSigDenominator
          ..metronomeOn = rt.metronomeOn
          ..syncOffsetMs = rt.syncOffsetMs
          ..speed = rt.speed
          ..done = rt.done
          ..photoPaths = rt.photoPaths
          ..updatedAt = rt.updatedAt;
        changed = true;
      }
    }

    // Apply tombstones to anything local that was deleted elsewhere later.
    _books.removeWhere((b) {
      final del = (_deleted[b.id] ?? 0) > b.updatedAt;
      if (del) changed = true;
      return del;
    });
    _tracks.removeWhere((t) {
      final del = (_deleted[t.id] ?? 0) > t.updatedAt;
      if (del) changed = true;
      return del;
    });

    if (changed) {
      _rehomePaths(); // normalise any merged paths into local dirs
      await save();
      notifyListeners();
    }
    return changed;
  }

  /// Replace the whole catalog (used when loading from Drive) and persist.
  Future<void> replaceCatalog(List<Book> books, List<Track> tracks) async {
    _books
      ..clear()
      ..addAll(books);
    _tracks
      ..clear()
      ..addAll(tracks);
    _deleted.clear(); // a full replace is a clean slate
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
      _deleted
        ..clear()
        ..addAll(((data['deleted'] as Map?) ?? {})
            .map((k, v) => MapEntry(k as String, (v as num).toInt())));
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
      'deleted': _deleted,
    };
    await _dbFile.writeAsString(jsonEncode(data));
  }

  // ─── Books ───

  Future<Book> createBook(String title) async {
    final book = Book(
      id: _newId(),
      title: title.trim().isEmpty ? 'Untitled book' : title.trim(),
      order: _books.length,
      updatedAt: _nowMs(),
    );
    _books.add(book);
    await save();
    notifyListeners();
    return book;
  }

  Future<void> renameBook(Book book, String title) async {
    if (title.trim().isEmpty) return;
    book.title = title.trim();
    book.updatedAt = _nowMs();
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
      book.updatedAt = _nowMs();
      await save();
      notifyListeners();
    } catch (e) {
      debugPrint('setBookCover error: $e');
    }
  }

  Future<void> removeBookCover(Book book) async {
    await _removeCoverFile(book);
    book.coverPath = null;
    book.updatedAt = _nowMs();
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
    final ts = _nowMs();
    await _removeCoverFile(book);
    for (final t in tracksForBook(book.id)) {
      await _deleteTrackFiles(t);
      _deleted[t.id] = ts;
      _tracks.remove(t);
    }
    _deleted[book.id] = ts;
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
          updatedAt: _nowMs(),
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
    t.updatedAt = _nowMs();
    await save();
    notifyListeners();
  }

  /// Move a track within its book. [newIndex] is already adjusted for the
  /// removed item (ReorderableListView's onReorderItem convention).
  Future<void> reorderTracks(String bookId, int oldIndex, int newIndex) async {
    final list = tracksForBook(bookId); // sorted by current order
    if (oldIndex < 0 || oldIndex >= list.length) return;
    newIndex = newIndex.clamp(0, list.length - 1);
    if (newIndex == oldIndex) return;
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    final now = _nowMs();
    for (var i = 0; i < list.length; i++) {
      if (list[i].order != i + 1) {
        list[i].order = i + 1;
        list[i].updatedAt = now; // so the new order syncs to other devices
      }
    }
    await save();
    notifyListeners();
  }

  /// Save a freshly recorded WAV as a new track in [bookId].
  Future<void> addRecordedTrack(
      String bookId, List<int> wavBytes, String title) async {
    final id = _newId();
    final dest = p.join(_audioDir.path, '$id.wav');
    await File(dest).writeAsBytes(wavBytes);
    _tracks.add(Track(
      id: id,
      bookId: bookId,
      title: title.trim().isEmpty ? 'Recording' : title.trim(),
      order: trackCount(bookId) + 1,
      audioPath: dest,
      updatedAt: _nowMs(),
    ));
    await save();
    notifyListeners();
  }

  Future<void> deleteTrack(Track t) async {
    _deleted[t.id] = _nowMs();
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
    t.updatedAt = _nowMs();
    await save();
    notifyListeners();
  }

  Future<void> removePhoto(Track t, String photoPath) async {
    t.photoPaths.remove(photoPath);
    t.updatedAt = _nowMs();
    try {
      final f = File(photoPath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await save();
    notifyListeners();
  }
}
