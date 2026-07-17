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
    final list = [..._books]
      ..sort((a, b) {
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
  String get audioDirPath => kIsWeb ? '' : _audioDir.path;
  String get photoDirPath => kIsWeb ? '' : _photoDir.path;
  String get coverDirPath => kIsWeb ? '' : _coverDir.path;

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
  Future<bool> mergeRemote(
    List<Book> remoteBooks,
    List<Track> remoteTracks,
    Map<String, int> remoteDeleted,
  ) async {
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
        ..addAll(
          trackList.map((e) => Track.fromJson(e as Map<String, dynamic>)),
        );
      _deleted
        ..clear()
        ..addAll(
          ((data['deleted'] as Map?) ?? {}).map(
            (k, v) => MapEntry(k as String, (v as num).toInt()),
          ),
        );
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
    final orphans = _tracks.where(
      (t) => t.bookId.isEmpty || !knownIds.contains(t.bookId),
    );
    if (orphans.isEmpty) return;
    final defaultBook = Book(id: _newId(), title: 'My Practice', order: 0);
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
  /// Returns the number of tracks added. [driveIds], when given, is a parallel
  /// list tagging each source with the Google Drive file id it came from (used
  /// to dedupe re-syncs of a linked Drive folder).
  Future<int> importAudioFiles(
    String bookId,
    List<String> sourcePaths, {
    List<String?>? driveIds,
  }) async {
    int added = 0;
    final existing = trackCount(bookId);
    for (var i = 0; i < sourcePaths.length; i++) {
      final src = sourcePaths[i];
      try {
        final ext = p.extension(src);
        final id = _newId();
        final dest = p.join(_audioDir.path, '$id$ext');
        await File(src).copy(dest);
        final (order, title) = Track.parseFileName(src);
        _tracks.add(
          Track(
            id: id,
            bookId: bookId,
            title: title,
            order: order == 0 ? existing + added + 1 : order,
            audioPath: dest,
            updatedAt: _nowMs(),
            driveId: driveIds != null && i < driveIds.length
                ? driveIds[i]
                : null,
          ),
        );
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

  // ─── Library sharing (export / import a self-contained package) ───

  static String _safeName(String s) {
    final cleaned = s.replaceAll(RegExp(r'[^\w\- ]'), '').trim();
    return cleaned.isEmpty ? 'library' : cleaned;
  }

  /// Everything the export isolate needs, as plain data: the manifest JSON plus
  /// the list of files to zip. Built on the main isolate (needs live library
  /// state); the isolate only reads files and writes the zip.
  Future<ExportSpec> buildExportSpec(
    List<Book> books, {
    List<Track>? onlyTracks,
    String? label,
  }) async {
    final manifestBooks = <Map<String, dynamic>>[];
    final manifestTracks = <Map<String, dynamic>>[];
    final files = <(String, String)>[];
    var totalBytes = 0;
    var trackCount = 0;

    Future<bool> addFile(String name, String path) async {
      final f = File(path);
      if (!await f.exists()) return false;
      files.add((name, path));
      totalBytes += await f.length();
      return true;
    }

    for (final b in books) {
      final bj = b.toJson()
        ..remove('driveFolderId')
        ..remove('driveFolderName');
      final cover = b.coverPath;
      if (cover != null) {
        final name = 'covers/${b.id}${p.extension(cover)}';
        if (await addFile(name, cover)) bj['_cover'] = name;
      }
      manifestBooks.add(bj);

      final tracks = onlyTracks != null
          ? onlyTracks.where((t) => t.bookId == b.id)
          : tracksForBook(b.id);
      for (final t in tracks) {
        final tj = t.toJson()..remove('driveId');
        final audioName = 'audio/${t.id}${p.extension(t.audioPath)}';
        if (await addFile(audioName, t.audioPath)) tj['_audio'] = audioName;
        final photoNames = <String>[];
        for (var i = 0; i < t.photoPaths.length; i++) {
          final name = 'photos/${t.id}_$i${p.extension(t.photoPaths[i])}';
          if (await addFile(name, t.photoPaths[i])) photoNames.add(name);
        }
        tj['_photos'] = photoNames;
        manifestTracks.add(tj);
        trackCount++;
      }
    }

    final manifestJson = jsonEncode({
      'format': 'metrosound-library',
      'version': 1,
      'books': manifestBooks,
      'tracks': manifestTracks,
    });
    final base =
        label ?? (books.length == 1 ? books.first.title : 'MetroSound Library');
    return ExportSpec(
      manifestJson: manifestJson,
      files: files,
      totalBytes: totalBytes,
      trackCount: trackCount,
      zipFileName: '${_safeName(base)}.metrosound.zip',
    );
  }

  /// The share identity of a manifest entry: the id it had where it was first
  /// created (originId survives re-shares), else its id in the package.
  static String manifestShareId(Map<String, dynamic> j) =>
      (j['originId'] as String?) ?? (j['id'] as String);

  /// The local book a package book should merge into, if any: strong match on
  /// share identity, soft match on title. Null → it's new to this library.
  Book? findMatchingBook(Map<String, dynamic> bj) {
    final sid = manifestShareId(bj);
    for (final b in _books) {
      if (b.shareId == sid) return b;
    }
    final title = ((bj['title'] as String?) ?? '').trim().toLowerCase();
    if (title.isEmpty) return null;
    for (final b in _books) {
      if (b.title.trim().toLowerCase() == title) return b;
    }
    return null;
  }

  /// Merge an already-extracted package subset into the library.
  /// [bookTargets] decides per package book: an existing local book id to
  /// APPEND into (duplicate tracks skipped by share identity/title), or null
  /// to import as a NEW book. [extracted] maps archive names to temp paths
  /// produced by the import isolate.
  Future<ImportResult> applyImport({
    required List<Map<String, dynamic>> manifestBooks,
    required List<Map<String, dynamic>> manifestTracks,
    required Map<String, String> extracted,
    Map<String, String?> bookTargets = const {},
  }) async {
    Future<String?> claim(
      String? archiveName,
      Directory destDir,
      String destBase,
    ) async {
      if (archiveName == null) return null;
      final src = extracted[archiveName];
      if (src == null || !await File(src).exists()) return null;
      final dest = p.join(destDir.path, '$destBase${p.extension(archiveName)}');
      await File(src).copy(dest);
      return dest;
    }

    final idMap = <String, String>{}; // pkg book id -> local book id
    final appended = <String>{}; // local book ids we're appending into
    var booksAdded = 0, booksMerged = 0, tracksAdded = 0, tracksSkipped = 0;

    for (final bj in manifestBooks) {
      final pkgId = bj['id'] as String;
      final targetId = bookTargets[pkgId];
      final target = targetId == null
          ? null
          : _books.where((b) => b.id == targetId).firstOrNull;
      if (target != null) {
        idMap[pkgId] = target.id;
        appended.add(target.id);
        booksMerged++;
        // Adopt the package cover only if the local book has none.
        if (target.coverPath == null ||
            !await File(target.coverPath!).exists()) {
          final cover = await claim(
            bj['_cover'] as String?,
            _coverDir,
            target.id,
          );
          if (cover != null) {
            target.coverPath = cover;
            target.updatedAt = _nowMs();
          }
        }
      } else {
        final newId = _newId();
        idMap[pkgId] = newId;
        _books.add(
          Book(
            id: newId,
            title: (bj['title'] as String?) ?? 'Shared book',
            order: _books.length,
            coverPath: await claim(bj['_cover'] as String?, _coverDir, newId),
            originId: manifestShareId(bj),
            updatedAt: _nowMs(),
          ),
        );
        booksAdded++;
      }
    }

    for (final tj in manifestTracks) {
      final localBookId = idMap[tj['bookId']];
      if (localBookId == null) continue;

      // Appending into an existing book: skip tracks it already has.
      if (appended.contains(localBookId)) {
        final sid = manifestShareId(tj);
        final title = ((tj['title'] as String?) ?? '').trim().toLowerCase();
        final dup = _tracks.any(
          (t) =>
              t.bookId == localBookId &&
              (t.shareId == sid || t.title.trim().toLowerCase() == title),
        );
        if (dup) {
          tracksSkipped++;
          continue;
        }
      }

      final newId = _newId();
      final audioPath = await claim(tj['_audio'] as String?, _audioDir, newId);
      if (audioPath == null) continue; // a track is nothing without its audio
      final photoPaths = <String>[];
      for (final pn in (tj['_photos'] as List?) ?? const []) {
        final ph = await claim(
          pn as String,
          _photoDir,
          '${newId}_${photoPaths.length}',
        );
        if (ph != null) photoPaths.add(ph);
      }
      _tracks.add(
        Track(
          id: newId,
          bookId: localBookId,
          title: (tj['title'] as String?) ?? 'Track',
          order: appended.contains(localBookId)
              ? trackCount(localBookId) +
                    1 // append at the end
              : (tj['order'] as num?)?.toInt() ?? 0,
          audioPath: audioPath,
          bpm: (tj['bpm'] as num?)?.toInt() ?? 80,
          beatsPerBar: (tj['beatsPerBar'] as num?)?.toInt() ?? 4,
          timeSigDenominator: (tj['timeSigDenominator'] as num?)?.toInt() ?? 4,
          metronomeOn: tj['metronomeOn'] as bool? ?? false,
          syncOffsetMs: (tj['syncOffsetMs'] as num?)?.toInt() ?? 0,
          speed: (tj['speed'] as num?)?.toDouble() ?? 1.0,
          done: false, // recipient starts fresh
          originId: manifestShareId(tj),
          updatedAt: _nowMs(),
          photoPaths: photoPaths,
        ),
      );
      tracksAdded++;
    }

    await save();
    notifyListeners();
    return ImportResult(
      booksAdded: booksAdded,
      booksMerged: booksMerged,
      tracksAdded: tracksAdded,
      tracksSkipped: tracksSkipped,
    );
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
    String bookId,
    List<int> wavBytes,
    String title,
  ) async {
    final id = _newId();
    final dest = p.join(_audioDir.path, '$id.wav');
    await File(dest).writeAsBytes(wavBytes);
    _tracks.add(
      Track(
        id: id,
        bookId: bookId,
        title: title.trim().isEmpty ? 'Recording' : title.trim(),
        order: trackCount(bookId) + 1,
        audioPath: dest,
        updatedAt: _nowMs(),
      ),
    );
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

/// Plain-data description of an export job, safe to hand to an isolate.
class ExportSpec {
  final String manifestJson;
  final List<(String, String)> files; // (archiveName, absolute file path)
  final int totalBytes;
  final int trackCount;
  final String zipFileName;
  const ExportSpec({
    required this.manifestJson,
    required this.files,
    required this.totalBytes,
    required this.trackCount,
    required this.zipFileName,
  });
}

/// Outcome of a package import, for user-facing summaries.
class ImportResult {
  final int booksAdded;
  final int booksMerged;
  final int tracksAdded;
  final int tracksSkipped;
  const ImportResult({
    required this.booksAdded,
    required this.booksMerged,
    required this.tracksAdded,
    required this.tracksSkipped,
  });

  String get summary {
    final parts = <String>[];
    if (booksAdded > 0) parts.add('$booksAdded new book(s)');
    if (booksMerged > 0) parts.add('updated $booksMerged existing book(s)');
    parts.add('$tracksAdded track(s) added');
    if (tracksSkipped > 0) parts.add('$tracksSkipped already in your library');
    return parts.join(' · ');
  }
}
