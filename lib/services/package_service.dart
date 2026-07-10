import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/book.dart';
import '../models/track.dart';
import 'library_store.dart';
import 'notifications.dart';

enum JobKind { export, import }

/// `ready` = an export zip is finished and waiting to be shared.
/// Imports go straight from running to done.
enum JobState { preparing, running, ready, done, failed, cancelled }

class PackageJob {
  final String id;
  final JobKind kind;
  final String scopeLabel; // e.g. 'Book "Ketab-e Aval"', 'Whole library'
  final int trackCount;
  JobState state = JobState.preparing;
  int filesDone = 0;
  int filesTotal = 0;
  int bytesDone = 0;
  int bytesTotal = 0;
  String? outputPath; // export result zip
  String? resultSummary; // import result, human-readable
  String? error;

  PackageJob({
    required this.id,
    required this.kind,
    required this.scopeLabel,
    required this.trackCount,
  });

  double get progress => filesTotal == 0 ? 0 : filesDone / filesTotal;
  bool get isActive =>
      state == JobState.preparing || state == JobState.running;
}

/// Parsed manifest of a package file, for the import preview UI.
class PackagePreview {
  final String zipPath;
  final String fileName;
  final List<Map<String, dynamic>> books;
  final List<Map<String, dynamic>> tracks;
  final Map<String, int> entrySizes; // archiveName -> uncompressed bytes

  PackagePreview({
    required this.zipPath,
    required this.books,
    required this.tracks,
    required this.entrySizes,
  }) : fileName = p.basename(zipPath);

  List<Map<String, dynamic>> tracksForBook(String bookId) =>
      tracks.where((t) => t['bookId'] == bookId).toList();

  int trackSize(Map<String, dynamic> t) =>
      (entrySizes[t['_audio']] ?? 0) +
      ((t['_photos'] as List?) ?? const [])
          .fold<int>(0, (s, n) => s + (entrySizes[n] ?? 0));
}

/// What the user checked in the import preview, plus the append/copy decision
/// per package book: [bookTargets] maps a package book id to the EXISTING
/// local book id to append into, or null to import it as a new book.
class ImportSelection {
  final Set<String> bookIds; // manifest book ids to import
  final Set<String> trackIds; // manifest track ids to import
  final Map<String, String?> bookTargets;
  const ImportSelection(this.bookIds, this.trackIds,
      {this.bookTargets = const {}});
  bool get isEmpty => bookIds.isEmpty;
}

/// Runs export/import package jobs in a background isolate with progress,
/// cancel, and notify-when-ready. Single job at a time.
///
/// iOS reality check: isolates are suspended shortly after the app is
/// backgrounded, so the "export ready" notification fires only when the job
/// finishes within the background grace window; otherwise the job simply
/// resumes and completes on next foreground.
class PackageService extends ChangeNotifier with WidgetsBindingObserver {
  LibraryStore? _lib;
  PackageJob? _job;
  Isolate? _isolate;
  SendPort? _control;
  Directory? _jobsRoot;
  bool _foreground = true;
  bool _pendingShare = false;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  PackageJob? get job => _job;
  bool get busy => _job?.isActive ?? false;
  bool get hasReadyExport =>
      _job != null &&
      _job!.kind == JobKind.export &&
      _job!.state == JobState.ready;

  /// True once, after a notification tap or foreground-resume surfaced a
  /// ready export; the overlay uses it to auto-open the progress sheet.
  bool consumePendingShare() {
    final v = _pendingShare;
    _pendingShare = false;
    return v;
  }

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    Notifications.onTap = _onNotificationTap;
    unawaited(Notifications.init());
    final tmp = await getTemporaryDirectory();
    _jobsRoot = Directory(p.join(tmp.path, 'metrosound_jobs'));
    // Sweep debris from crashed/killed sessions.
    try {
      if (await _jobsRoot!.exists()) {
        await _jobsRoot!.delete(recursive: true);
      }
    } catch (_) {}
    await _jobsRoot!.create(recursive: true);
  }

  void attachLibrary(LibraryStore lib) => _lib = lib;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && hasReadyExport) {
      _pendingShare = true;
      Notifications.cancelExportReady();
      notifyListeners();
    }
  }

  void _onNotificationTap() {
    if (hasReadyExport) {
      _pendingShare = true;
      notifyListeners();
    }
  }

  // ─── Export ───

  /// Export whole books. Returns false if another job is running.
  Future<bool> startExportBooks(List<Book> books, {String? label}) =>
      _startExport(books: books, label: label);

  /// Export a single track (as a one-track copy of its parent book).
  Future<bool> startExportTrack(Book book, Track track) => _startExport(
      books: [book], onlyTracks: [track], label: track.title);

  Future<bool> _startExport(
      {required List<Book> books,
      List<Track>? onlyTracks,
      String? label}) async {
    final lib = _lib;
    if (lib == null || busy) return false;
    unawaited(Notifications.requestPermissionOnce());
    _clearFinishedJob();

    final scope = onlyTracks != null
        ? 'Track "${onlyTracks.first.title}"'
        : books.length == 1
            ? 'Book "${books.first.title}"'
            : 'Whole library (${books.length} books)';
    final job = PackageJob(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      kind: JobKind.export,
      scopeLabel: scope,
      trackCount: 0,
    );
    _job = job;
    notifyListeners();

    try {
      final spec =
          await lib.buildExportSpec(books, onlyTracks: onlyTracks, label: label);
      final dir =
          await Directory(p.join(_jobsRoot!.path, job.id)).create(recursive: true);
      final zipPath = p.join(dir.path, spec.zipFileName);
      _job = PackageJob(
        id: job.id,
        kind: JobKind.export,
        scopeLabel: scope,
        trackCount: spec.trackCount,
      )
        ..state = JobState.running
        ..filesTotal = spec.files.length + 1 // + manifest
        ..bytesTotal = spec.totalBytes;
      notifyListeners();

      final receive = ReceivePort();
      _isolate = await Isolate.spawn(_exportEntry, {
        'send': receive.sendPort,
        'zipPath': zipPath,
        'manifest': spec.manifestJson,
        'files': [
          for (final (name, path) in spec.files) [name, path]
        ],
      });
      _listen(receive, onOk: (msg) {
        _job!
          ..state = JobState.ready
          ..outputPath = msg['path'] as String;
        if (_foreground) {
          _pendingShare = true;
        } else {
          Notifications.showExportReady(scope);
        }
      });
      return true;
    } catch (e) {
      _fail('$e');
      return true; // job exists, in failed state
    }
  }

  // ─── Import ───

  /// Read only the manifest + entry sizes of a package (fast, no extraction).
  /// Throws [FormatException] if the file isn't a Metro Sound package.
  Future<PackagePreview> readPreview(String zipPath) async {
    final result = await Isolate.run(() => _readManifest(zipPath));
    final manifest = jsonDecode(result['manifest'] as String);
    if (manifest is! Map || manifest['format'] != 'metrosound-library') {
      throw const FormatException('Not a Metro Sound library file');
    }
    return PackagePreview(
      zipPath: zipPath,
      books: ((manifest['books'] as List?) ?? const [])
          .cast<Map<String, dynamic>>(),
      tracks: ((manifest['tracks'] as List?) ?? const [])
          .cast<Map<String, dynamic>>(),
      entrySizes: (result['sizes'] as Map).cast<String, int>(),
    );
  }

  /// Extract + merge the selected subset of [preview]. False if busy.
  Future<bool> startImport(
      PackagePreview preview, ImportSelection selection) async {
    final lib = _lib;
    if (lib == null || busy || selection.isEmpty) return false;
    _clearFinishedJob();

    final books = preview.books
        .where((b) => selection.bookIds.contains(b['id']))
        .toList();
    final tracks = preview.tracks
        .where((t) => selection.trackIds.contains(t['id']))
        .toList();

    // Archive entries the selection actually needs.
    final wanted = <String>[
      for (final b in books)
        if (b['_cover'] is String) b['_cover'] as String,
      for (final t in tracks) ...[
        if (t['_audio'] is String) t['_audio'] as String,
        ...((t['_photos'] as List?) ?? const []).cast<String>(),
      ],
    ];

    final job = PackageJob(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      kind: JobKind.import,
      scopeLabel: 'Import ${books.length} book(s), ${tracks.length} track(s)',
      trackCount: tracks.length,
    )
      ..state = JobState.running
      ..filesTotal = wanted.length
      ..bytesTotal =
          wanted.fold(0, (s, n) => s + (preview.entrySizes[n] ?? 0));
    _job = job;
    notifyListeners();

    final destDir =
        await Directory(p.join(_jobsRoot!.path, job.id)).create(recursive: true);
    final receive = ReceivePort();
    _isolate = await Isolate.spawn(_importEntry, {
      'send': receive.sendPort,
      'zipPath': preview.zipPath,
      'names': wanted,
      'destDir': destDir.path,
    });
    _listen(receive, onOk: (msg) async {
      final extracted = (msg['files'] as Map).cast<String, String>();
      try {
        final result = await lib.applyImport(
          manifestBooks: books,
          manifestTracks: tracks,
          extracted: extracted,
          bookTargets: selection.bookTargets,
        );
        _job!
          ..state = JobState.done
          ..resultSummary = result.summary;
      } catch (e) {
        _job!
          ..state = JobState.failed
          ..error = '$e';
      }
      try {
        await destDir.delete(recursive: true);
      } catch (_) {}
    });
    return true;
  }

  // ─── Shared machinery ───

  void _listen(ReceivePort receive,
      {required FutureOr<void> Function(Map msg) onOk}) {
    receive.listen((raw) async {
      final msg = raw as Map;
      switch (msg['type']) {
        case 'hello':
          _control = msg['control'] as SendPort;
          break;
        case 'progress':
          final j = _job;
          if (j == null) break;
          j
            ..filesDone = msg['done'] as int
            ..bytesDone = msg['bytes'] as int;
          // Throttle UI updates to ~10/s.
          final now = DateTime.now();
          if (now.difference(_lastNotify).inMilliseconds > 100) {
            _lastNotify = now;
            notifyListeners();
          }
          break;
        case 'ok':
          await onOk(msg);
          _finishIsolate(receive);
          notifyListeners();
          break;
        case 'cancelled':
          _job?.state = JobState.cancelled;
          _finishIsolate(receive);
          notifyListeners();
          break;
        case 'error':
          _job
            ?..state = JobState.failed
            ..error = msg['message'] as String?;
          _finishIsolate(receive);
          notifyListeners();
          break;
      }
    });
  }

  void _finishIsolate(ReceivePort receive) {
    receive.close();
    _isolate = null;
    _control = null;
  }

  void _fail(String message) {
    _job
      ?..state = JobState.failed
      ..error = message;
    notifyListeners();
  }

  /// Ask the running isolate to stop (checked between files); hard-kill as a
  /// fallback if it doesn't answer within 2s.
  Future<void> cancel() async {
    final j = _job;
    if (j == null || !j.isActive) return;
    _control?.send('cancel');
    final iso = _isolate;
    unawaited(Future.delayed(const Duration(seconds: 2), () async {
      if (_isolate == iso && iso != null && _job?.isActive == true) {
        iso.kill(priority: Isolate.immediate);
        _isolate = null;
        _control = null;
        _job?.state = JobState.cancelled;
        await _deleteJobDir(j.id);
        notifyListeners();
      }
    }));
  }

  /// Drop the current (non-active) job and its temp files.
  void dismissJob() {
    final j = _job;
    if (j == null || j.isActive) return;
    _job = null;
    _pendingShare = false;
    Notifications.cancelExportReady();
    unawaited(_deleteJobDir(j.id));
    notifyListeners();
  }

  void _clearFinishedJob() {
    final j = _job;
    if (j != null && !j.isActive) {
      unawaited(_deleteJobDir(j.id));
      _job = null;
    }
    _pendingShare = false;
  }

  Future<void> _deleteJobDir(String id) async {
    try {
      final d = Directory(p.join(_jobsRoot!.path, id));
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }
}

// ─── Isolate entry points (top-level, no Flutter dependencies) ───

/// Streams files into a zip on disk (store level — audio is already
/// compressed). Sends progress per file; polls a cancel flag between files.
Future<void> _exportEntry(Map args) async {
  final send = args['send'] as SendPort;
  final zipPath = args['zipPath'] as String;
  final files = (args['files'] as List).cast<List>();

  var cancelled = false;
  final control = ReceivePort();
  control.listen((msg) {
    if (msg == 'cancel') cancelled = true;
  });
  send.send({'type': 'hello', 'control': control.sendPort});

  try {
    final enc = ZipFileEncoder();
    enc.create(zipPath, level: ZipFileEncoder.store);
    final manifestBytes = utf8.encode(args['manifest'] as String);
    enc.addArchiveFile(ArchiveFile.bytes('manifest.json', manifestBytes));
    var done = 1;
    var bytes = manifestBytes.length;
    send.send({'type': 'progress', 'done': done, 'bytes': bytes});

    for (final entry in files) {
      if (cancelled) {
        await enc.close();
        try {
          File(zipPath).deleteSync();
        } catch (_) {}
        send.send({'type': 'cancelled'});
        control.close();
        return;
      }
      final name = entry[0] as String;
      final path = entry[1] as String;
      final f = File(path);
      await enc.addFile(f, name, ZipFileEncoder.store);
      done++;
      bytes += f.existsSync() ? f.lengthSync() : 0;
      send.send({'type': 'progress', 'done': done, 'bytes': bytes});
    }
    await enc.close();
    send.send({'type': 'ok', 'path': zipPath});
  } catch (e) {
    try {
      File(zipPath).deleteSync();
    } catch (_) {}
    send.send({'type': 'error', 'message': _friendlyIoError(e)});
  }
  control.close();
}

/// Selectively extracts [names] from the zip to [destDir], streaming each
/// entry to disk (no whole-archive decompression).
Future<void> _importEntry(Map args) async {
  final send = args['send'] as SendPort;
  final zipPath = args['zipPath'] as String;
  final names = (args['names'] as List).cast<String>();
  final destDir = args['destDir'] as String;

  var cancelled = false;
  final control = ReceivePort();
  control.listen((msg) {
    if (msg == 'cancel') cancelled = true;
  });
  send.send({'type': 'hello', 'control': control.sendPort});

  InputFileStream? input;
  try {
    input = InputFileStream(zipPath);
    final archive = ZipDecoder().decodeStream(input);
    final out = <String, String>{};
    var done = 0;
    var bytes = 0;
    for (final name in names) {
      if (cancelled) {
        await input.close();
        send.send({'type': 'cancelled'});
        control.close();
        return;
      }
      final entry = archive.find(name);
      if (entry == null) continue; // tolerated: applyImport skips missing files
      // Flatten the archive path into a unique local file name.
      final dest =
          '$destDir${Platform.pathSeparator}${name.replaceAll('/', '_')}';
      final output = OutputFileStream(dest);
      entry.writeContent(output);
      await output.close();
      out[name] = dest;
      done++;
      bytes += entry.size;
      send.send({'type': 'progress', 'done': done, 'bytes': bytes});
    }
    await input.close();
    send.send({'type': 'ok', 'files': out});
  } catch (e) {
    try {
      await input?.close();
    } catch (_) {}
    send.send({'type': 'error', 'message': _friendlyIoError(e)});
  }
  control.close();
}

/// Manifest + entry sizes only — runs via Isolate.run (short, no progress).
Map<String, Object> _readManifest(String zipPath) {
  final input = InputFileStream(zipPath);
  try {
    final archive = ZipDecoder().decodeStream(input);
    final mf = archive.find('manifest.json');
    if (mf == null) throw const FormatException('No manifest');
    final sizes = <String, int>{
      for (final f in archive.files) f.name: f.size,
    };
    return {
      'manifest': utf8.decode(mf.readBytes() ?? []),
      'sizes': sizes,
    };
  } finally {
    input.closeSync();
  }
}

String _friendlyIoError(Object e) {
  if (e is FileSystemException) {
    return 'File error — check free space and try again';
  }
  return '$e';
}
