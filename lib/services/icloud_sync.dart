import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:icloud_storage/icloud_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/book.dart';
import '../models/track.dart';
import 'library_store.dart';

/// High-level state for the Settings UI.
enum ICloudState { off, unavailable, idle, syncing, synced, error }

/// Two-way iCloud sync for the whole library, stored in the app's PRIVATE
/// iCloud Drive container — the data lives under the user's own iCloud account
/// and we run no backend.
///
/// This is a transport twin of [DriveSyncService]: it reuses the sync engine
/// already baked into [LibraryStore] — `catalogSignature()`, `mergeRemote()`
/// (last-write-wins per entity + tombstones), and the basename-keyed media
/// convention — and only swaps the file transport for the `icloud_storage`
/// ubiquity-container API.
///
/// Container layout (relative to the container's Documents):
///   `library.json`      — the catalog payload (below)
///   `audio/<basename>`  — track audio, keyed by basename (immutable per id)
///   `photos/<basename>` — sheet photos
///   `covers/<basename>` — book covers
///
/// Catalog payload = local library.json + `signature` (convergence hash) and
/// `writer` (device id, so a device doesn't pull its own push back).
class ICloudSyncService extends ChangeNotifier {
  ICloudSyncService({String? containerId})
      : _containerId =
            containerId ?? 'iCloud.ca.nexthorizontechnologies.metrosound.app';

  final String _containerId;
  static const _catalogName = 'library.json';
  static const _audioPrefix = 'audio/';
  static const _photoPrefix = 'photos/';
  static const _coverPrefix = 'covers/';

  LibraryStore? _lib;

  bool get supported => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  bool _available = false; // iCloud account + container reachable
  bool get available => _available;

  bool _autoSync = false;
  bool get autoSync => _autoSync;

  String? _error;
  String? get error => _error;

  ICloudState _state = ICloudState.off;
  ICloudState get state => _state;

  DateTime? _lastSyncedAt;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  // ── Convergence bookkeeping (mirrors DriveSyncService) ──
  String _deviceId = '';
  int _syncedSignature = 0; // local state confirmed uploaded
  int _lastSeenRemoteSig = 0; // remote signature already merged/seen
  DateTime? _remoteMtime; // library.json contentChangeDate last read
  final Set<String> _uploadedMedia = {}; // relative paths already pushed

  Timer? _debounce;
  Timer? _poll;
  bool _inSync = false;
  bool _pendingPush = false;

  File? _prefsFile;

  // ── Lifecycle ──────────────────────────────────────────────────────────

  Future<void> init() async {
    if (!supported) {
      _setState(ICloudState.unavailable);
      return;
    }
    await _probeAvailability();
  }

  Future<void> _probeAvailability() async {
    try {
      // gather() throws if there is no signed-in iCloud account or the
      // container isn't provisioned; success (even empty) means we're good.
      await ICloudStorage.gather(containerId: _containerId);
      _available = true;
      _error = null;
    } catch (e) {
      _available = false;
      _error = 'iCloud isn\'t available. Sign in to iCloud in Settings and '
          'make sure iCloud Drive is on.';
      debugPrint('iCloud probe failed: $e');
    }
    if (!_available) {
      _setState(ICloudState.unavailable);
    } else if (_state == ICloudState.unavailable || _state == ICloudState.off) {
      _setState(_autoSync ? ICloudState.idle : ICloudState.off);
    }
    notifyListeners();
  }

  /// Wire the library in so edits trigger a debounced sync (mirrors Drive).
  Future<void> attachLibrary(LibraryStore library) async {
    _lib = library;
    await _loadPrefs();
    if (_deviceId.isEmpty) {
      _deviceId = _genId();
      await _savePrefs();
    }
    library.addListener(_onLibraryChanged);
    if (_autoSync && _available) {
      _startPoll();
      unawaited(_syncCycle(initial: true));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _poll?.cancel();
    _lib?.removeListener(_onLibraryChanged);
    super.dispose();
  }

  // ── Public controls (Settings UI) ──────────────────────────────────────

  Future<void> setAutoSync(bool on) async {
    if (on && !_available) {
      await _probeAvailability();
      if (!_available) return;
    }
    _autoSync = on;
    await _savePrefs();
    if (on) {
      _setState(ICloudState.idle);
      _startPoll();
      await _syncCycle(initial: true);
    } else {
      _debounce?.cancel();
      _poll?.cancel();
      _setState(ICloudState.off);
    }
    notifyListeners();
  }

  /// Manual "Sync now".
  Future<void> syncNow() async {
    if (!_available) await _probeAvailability();
    if (_available) await _syncCycle(initial: true);
  }

  // ── Change observation ─────────────────────────────────────────────────

  void _onLibraryChanged() {
    if (!_autoSync || _inSync || _lib == null) return;
    if (_lib!.catalogSignature() == _syncedSignature) return; // nothing new
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () => _syncCycle());
  }

  void _startPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _syncCycle());
  }

  // ── The cycle: pull-merge then push if we're ahead ─────────────────────

  Future<void> _syncCycle({bool initial = false}) async {
    if (!_autoSync || !_available || _inSync || _lib == null) return;
    _inSync = true;
    _setState(ICloudState.syncing);
    try {
      await _pullMerge();
      final sig = _lib!.catalogSignature();
      if (initial || _pendingPush || sig != _syncedSignature) {
        await _pushCatalog();
      }
      _pendingPush = false;
      _lastSyncedAt = _now();
      _error = null;
      _setState(ICloudState.synced);
    } catch (e) {
      // Keep trying on the next poll (covers offline edits).
      _pendingPush = true;
      _error = '$e';
      _setState(ICloudState.error);
      debugPrint('iCloud sync cycle failed: $e');
    } finally {
      _inSync = false;
    }
  }

  // ── Push ───────────────────────────────────────────────────────────────

  Future<void> _pushCatalog() async {
    final lib = _lib!;
    final sig = lib.catalogSignature();

    // Upload media first so the catalog never references a not-yet-present file.
    await _pushMedia(lib);

    final payload = {
      'books': lib.allBooks.map((b) => b.toJson()).toList(),
      'tracks': lib.allTracks.map((t) => t.toJson()).toList(),
      'deleted': lib.tombstones,
      'signature': sig,
      'writer': _deviceId,
    };
    final tmp = await getTemporaryDirectory();
    final f = File(p.join(tmp.path, 'icloud_library_out.json'));
    await f.writeAsString(jsonEncode(payload));
    await ICloudStorage.upload(
      containerId: _containerId,
      filePath: f.path,
      destinationRelativePath: _catalogName,
    );

    _syncedSignature = sig;
    _lastSeenRemoteSig = sig; // don't pull our own push back
    await _savePrefs();
  }

  Future<void> _pushMedia(LibraryStore lib) async {
    final wanted = <String, String>{}; // relativePath -> local path
    for (final t in lib.allTracks) {
      if (t.audioPath.isNotEmpty) {
        wanted['$_audioPrefix${p.basename(t.audioPath)}'] = t.audioPath;
      }
      for (final ph in t.photoPaths) {
        wanted['$_photoPrefix${p.basename(ph)}'] = ph;
      }
    }
    for (final b in lib.allBooks) {
      final c = b.coverPath;
      if (c != null && c.isNotEmpty) {
        wanted['$_coverPrefix${p.basename(c)}'] = c;
      }
    }
    for (final entry in wanted.entries) {
      if (_uploadedMedia.contains(entry.key)) continue;
      if (!File(entry.value).existsSync()) continue;
      await ICloudStorage.upload(
        containerId: _containerId,
        filePath: entry.value,
        destinationRelativePath: entry.key,
      );
      _uploadedMedia.add(entry.key);
    }
  }

  // ── Pull ───────────────────────────────────────────────────────────────

  Future<void> _pullMerge() async {
    final lib = _lib!;
    final files = await ICloudStorage.gather(containerId: _containerId);
    final catalog = _fileFor(files, _catalogName);
    if (catalog == null) return; // nothing uploaded yet

    // Cheap change check: skip if the catalog hasn't changed since last pull.
    if (_remoteMtime != null &&
        !catalog.contentChangeDate.isAfter(_remoteMtime!)) {
      return;
    }

    final payload = await _downloadCatalog();
    if (payload == null) return;

    final remoteSig = (payload['signature'] as num?)?.toInt() ?? 0;
    _remoteMtime = catalog.contentChangeDate;
    if (remoteSig != 0 && remoteSig == _lastSeenRemoteSig) {
      return; // already merged this state (or it's our own push)
    }

    final remoteBooks = ((payload['books'] as List?) ?? const [])
        .map((j) => Book.fromJson(j as Map<String, dynamic>))
        .toList();
    final remoteTracks = ((payload['tracks'] as List?) ?? const [])
        .map((j) => Track.fromJson(j as Map<String, dynamic>))
        .toList();
    final remoteDeleted = <String, int>{};
    ((payload['deleted'] as Map?) ?? const {}).forEach((k, v) {
      final ts = (v as num?)?.toInt();
      if (ts != null) remoteDeleted['$k'] = ts;
    });

    // Ensure every referenced media file is present locally, then rewrite the
    // remote entities' paths to their local copies (mergeRemote expects local
    // paths; media is immutable per basename so an existing file is the same).
    await _ensureMediaLocal(lib, remoteBooks, remoteTracks, remoteDeleted);

    await lib.mergeRemote(remoteBooks, remoteTracks, remoteDeleted);
    _lastSeenRemoteSig = remoteSig;
    await _savePrefs();
  }

  Future<void> _ensureMediaLocal(
    LibraryStore lib,
    List<Book> books,
    List<Track> tracks,
    Map<String, int> remoteDeleted,
  ) async {
    for (final t in tracks) {
      if (remoteDeleted.containsKey(t.id)) continue;
      if (t.audioPath.isNotEmpty) {
        final base = p.basename(t.audioPath);
        final local = p.join(lib.audioDirPath, base);
        await _downloadToLocal('$_audioPrefix$base', local);
        t.audioPath = local;
      }
      if (t.photoPaths.isNotEmpty) {
        final rebased = <String>[];
        for (final ph in t.photoPaths) {
          final base = p.basename(ph);
          final local = p.join(lib.photoDirPath, base);
          await _downloadToLocal('$_photoPrefix$base', local);
          rebased.add(local);
        }
        t.photoPaths
          ..clear()
          ..addAll(rebased);
      }
    }
    for (final b in books) {
      final c = b.coverPath;
      if (c != null && c.isNotEmpty && !remoteDeleted.containsKey(b.id)) {
        final base = p.basename(c);
        final local = p.join(lib.coverDirPath, base);
        await _downloadToLocal('$_coverPrefix$base', local);
        b.coverPath = local;
      }
    }
  }

  // ── Transport helpers ──────────────────────────────────────────────────

  ICloudFile? _fileFor(List<ICloudFile> files, String relativePath) {
    for (final f in files) {
      if (f.relativePath == relativePath) return f;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _downloadCatalog() async {
    final tmp = await getTemporaryDirectory();
    final local = p.join(tmp.path, 'icloud_library_in.json');
    try {
      File(local).deleteSync(); // always fetch the freshest catalog
    } catch (_) {}
    final ok = await _downloadToLocal(_catalogName, local, force: true);
    if (!ok) return null;
    try {
      return jsonDecode(await File(local).readAsString())
          as Map<String, dynamic>;
    } catch (e) {
      debugPrint('iCloud catalog parse failed: $e');
      return null;
    }
  }

  /// Download [relativePath] to [localPath] and wait until it's actually on
  /// disk. Media basenames are immutable, so an existing local file is skipped
  /// unless [force] (used for the catalog, which changes in place).
  Future<bool> _downloadToLocal(String relativePath, String localPath,
      {bool force = false}) async {
    final f = File(localPath);
    if (!force && f.existsSync()) return true;
    final done = Completer<void>();
    try {
      await ICloudStorage.download(
        containerId: _containerId,
        relativePath: relativePath,
        destinationFilePath: localPath,
        onProgress: (stream) {
          stream.listen(
            (progress) {
              if (progress >= 1.0 && !done.isCompleted) done.complete();
            },
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
            onError: (Object e) {
              if (!done.isCompleted) done.completeError(e);
            },
          );
        },
      );
      // Some downloads complete before the listener attaches; bound the wait.
      await done.future.timeout(const Duration(seconds: 90), onTimeout: () {});
    } catch (e) {
      debugPrint('iCloud download failed ($relativePath): $e');
    }
    return f.existsSync();
  }

  // ── Prefs persistence (device-local convergence state) ─────────────────

  Future<void> _loadPrefs() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _prefsFile = File(p.join(dir.path, 'icloud_sync.json'));
      if (await _prefsFile!.exists()) {
        final j = jsonDecode(await _prefsFile!.readAsString())
            as Map<String, dynamic>;
        _deviceId = (j['deviceId'] as String?) ?? '';
        _autoSync = j['autoSync'] == true;
        _syncedSignature = (j['syncedSignature'] as num?)?.toInt() ?? 0;
        _lastSeenRemoteSig = (j['lastSeenRemoteSig'] as num?)?.toInt() ?? 0;
        _uploadedMedia
          ..clear()
          ..addAll(((j['uploadedMedia'] as List?) ?? const []).cast<String>());
      }
    } catch (e) {
      debugPrint('iCloud prefs load failed: $e');
    }
  }

  Future<void> _savePrefs() async {
    try {
      await _prefsFile?.writeAsString(jsonEncode({
        'deviceId': _deviceId,
        'autoSync': _autoSync,
        'syncedSignature': _syncedSignature,
        'lastSeenRemoteSig': _lastSeenRemoteSig,
        'uploadedMedia': _uploadedMedia.toList(),
      }));
    } catch (_) {}
  }

  // ── Utils ──────────────────────────────────────────────────────────────

  void _setState(ICloudState s) {
    if (s == _state) return;
    _state = s;
    notifyListeners();
  }

  DateTime _now() => DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch);

  String _genId() {
    final r = math.Random();
    final n = DateTime.now().microsecondsSinceEpoch ^ r.nextInt(1 << 32);
    return n.toRadixString(36);
  }
}
