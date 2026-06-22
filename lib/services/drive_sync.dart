import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/google_config.dart';
import '../models/book.dart';
import '../models/track.dart';
import 'library_store.dart';

/// Backs up the whole catalog (audio + photos + covers + metadata) to a visible
/// "Metro Sound" folder in the user's Google Drive, and loads it back. Manual
/// push/pull — no background sync. Uses the least-privilege drive.file scope.
class DriveSyncService extends ChangeNotifier {
  static const _folderName = 'Metro Sound';
  static const _libraryFile = 'library.json';
  static const _scopes = [drive.DriveApi.driveFileScope];

  final http.Client _baseClient = http.Client();
  AccessCredentials? _creds;
  AutoRefreshingAuthClient? _authClient;
  String? _accountLabel;

  // iOS/Android use native Google Sign-In (returns to the app); macOS uses the
  // desktop loopback flow above.
  final GoogleSignIn _gsi = GoogleSignIn(scopes: _scopes);
  GoogleSignInAccount? _gsiUser;
  bool get _useGsi => !kIsWeb && Platform.isIOS;

  late File _credsFile;

  bool _busy = false;
  String _status = '';
  double? _progress; // 0..1 during a transfer, null otherwise

  // ─── Auto-sync (two-way) state ───
  LibraryStore? _lib;
  bool _autoSync = false;
  String? _autoFolderId;
  String? _autoFolderName;
  String _deviceId = '';
  int _syncedSignature = 0; // local state we've confirmed is up on Drive
  int _lastSeenRemoteSig = 0; // last remote state we processed
  String _remoteMtime = ''; // Drive modifiedTime of the last catalog we read
  final Set<String> _uploadedMedia = {}; // media basenames already on Drive
  File? _syncPrefsFile;

  Timer? _debounce; // coalesces rapid local edits into one push
  Timer? _poll; // periodic pull of remote changes
  bool _inSync = false; // serialises push/pull so they never overlap
  bool _pendingPush = false; // a push is owed (e.g. failed while offline)
  String _autoState = ''; // short status for the auto-sync UI row

  bool get autoSyncEnabled => _autoSync;
  String get autoSyncState => _autoState;

  bool get configured => _useGsi ? googleIosConfigured : googleConfigured;
  bool get isConnected => _useGsi ? _gsiUser != null : _creds != null;
  String? get accountLabel => _accountLabel;
  bool get busy => _busy;
  String get status => _status;
  double? get progress => _progress;

  ClientId get _clientId => ClientId(googleClientId, googleClientSecret);

  Future<void> init() async {
    if (_useGsi) {
      try {
        _gsiUser = await _gsi.signInSilently();
        _accountLabel = _gsiUser?.email;
      } catch (e) {
        debugPrint('Google silent sign-in: $e');
      }
      notifyListeners();
      return;
    }
    final dir = await getApplicationSupportDirectory();
    _credsFile = File(p.join(dir.path, 'google_creds.json'));
    await _loadCreds();
    if (_creds != null) {
      _authClient = autoRefreshingClient(_clientId, _creds!, _baseClient);
      // Don't block startup on the network; refresh the label in the background.
      unawaited(_refreshAccountLabel());
    }
  }

  // ─── Auth ───

  Future<void> connect() async {
    if (!configured) return;
    if (_useGsi) {
      _setBusy(true, 'Signing in…');
      try {
        _gsiUser = await _gsi.signIn();
        if (_gsiUser != null) {
          _accountLabel = _gsiUser!.email;
          _setStatus('Connected as $_accountLabel');
          _resumeAutoSyncIfEnabled();
        } else {
          _setStatus('Sign-in cancelled');
        }
      } catch (e) {
        _setStatus('Sign-in failed: $e');
        debugPrint('Google sign-in error: $e');
      } finally {
        _setBusy(false);
      }
      return;
    }
    _setBusy(true, 'Opening browser for Google sign-in…');
    try {
      _creds = await obtainAccessCredentialsViaUserConsent(
        _clientId,
        _scopes,
        _baseClient,
        _promptUser,
      );
      _authClient = autoRefreshingClient(_clientId, _creds!, _baseClient);
      await _saveCreds();
      await _refreshAccountLabel();
      _setStatus('Connected${_accountLabel != null ? ' as $_accountLabel' : ''}');
      _resumeAutoSyncIfEnabled();
    } catch (e) {
      _setStatus('Sign-in failed: $e');
      debugPrint('Drive connect error: $e');
    } finally {
      _setBusy(false);
    }
  }

  void _resumeAutoSyncIfEnabled() {
    if (_autoSync && _lib != null) {
      _startPoll();
      unawaited(_syncCycle(initial: true));
    }
  }

  Future<void> disconnect() async {
    _stopPoll();
    _debounce?.cancel();
    if (_useGsi) {
      try {
        await _gsi.disconnect();
      } catch (_) {}
      _gsiUser = null;
      _accountLabel = null;
      _setStatus('Disconnected');
      return;
    }
    _creds = null;
    _authClient = null;
    _accountLabel = null;
    try {
      if (await _credsFile.exists()) await _credsFile.delete();
    } catch (_) {}
    _setStatus('Disconnected');
  }

  void _promptUser(String url) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _refreshAccountLabel() async {
    try {
      final api = drive.DriveApi(_authClient!);
      final about = await api.about.get($fields: 'user');
      _accountLabel = about.user?.emailAddress ?? about.user?.displayName;
      notifyListeners();
    } catch (e) {
      debugPrint('about.get failed: $e');
    }
  }

  /// The Drive API authenticated for the current platform's sign-in, or null if
  /// not connected.
  Future<drive.DriveApi?> _api() async {
    if (_useGsi) {
      final client = await _gsi.authenticatedClient();
      if (client == null) return null;
      return drive.DriveApi(client);
    }
    if (_authClient == null) return null;
    return drive.DriveApi(_authClient!);
  }

  // ─── Folders ───

  /// Top-level folders the app created, for the backup/load picker.
  Future<List<({String id, String name})>> listFolders() async {
    final api = await _api();
    if (api == null) return [];
    final out = <({String id, String name})>[];
    String? token;
    try {
      do {
        final res = await api.files.list(
          q: "mimeType='application/vnd.google-apps.folder' and "
              "trashed=false and 'root' in parents",
          $fields: 'nextPageToken, files(id,name)',
          pageSize: 100,
          pageToken: token,
          spaces: 'drive',
        );
        for (final f in res.files ?? const <drive.File>[]) {
          if (f.id != null && f.name != null) {
            out.add((id: f.id!, name: f.name!));
          }
        }
        token = res.nextPageToken;
      } while (token != null);
    } catch (e) {
      debugPrint('listFolders error: $e');
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  // ─── Backup (push) ───

  /// Backs up into [folderId] if given, else a folder named [folderName]
  /// (created if needed), else the default "Metro Sound" folder.
  Future<bool> backup(LibraryStore library,
      {String? folderId, String? folderName}) async {
    final api = await _api();
    if (api == null) {
      _setStatus('Not connected');
      return false;
    }
    // Never let an empty device overwrite a real backup's library.json.
    if (library.allBooks.isEmpty && library.allTracks.isEmpty) {
      _setStatus('Nothing to back up — this device has no books yet.');
      return false;
    }
    _setBusy(true, 'Preparing backup…');
    try {
      final rootId =
          await _dataRoot(api, folderId: folderId, folderName: folderName);
      final rootIndex = await _folderIndex(api, rootId);

      // Total = library.json + every cover + every audio + every photo.
      var total = 1;
      for (final b in library.allBooks) {
        if (b.coverPath != null) total++;
      }
      for (final t in library.allTracks) {
        total += 1 + t.photoPaths.length;
      }
      var done = 0;

      // library.json lives at the root of the "Metro Sound" folder.
      final libraryJson = jsonEncode(_catalogPayload(library));
      await _uploadBytes(api, rootId, _libraryFile, utf8.encode(libraryJson),
          rootIndex[_libraryFile], 'application/json');
      done++;
      _setProgress(done / total, 'Backing up… ($done/$total)');

      // One subfolder per book, mirroring the in-app structure.
      for (final b in library.allBooks) {
        final bookFolderId =
            await _ensureFolder(api, _bookFolderName(b), parentId: rootId);
        final bookIndex = await _folderIndex(api, bookFolderId);

        if (b.coverPath != null) {
          await _uploadIfMissing(api, bookFolderId, bookIndex, b.coverPath!);
          done++;
          _setProgress(done / total, 'Backing up… ($done/$total)');
        }

        for (final t in library.allTracks.where((t) => t.bookId == b.id)) {
          await _uploadIfMissing(api, bookFolderId, bookIndex, t.audioPath);
          done++;
          _setProgress(done / total, 'Backing up… ($done/$total)');
          for (final ph in t.photoPaths) {
            await _uploadIfMissing(api, bookFolderId, bookIndex, ph);
            done++;
            _setProgress(done / total, 'Backing up… ($done/$total)');
          }
        }
      }

      _setStatus('Backup complete — saved to Drive in ${library.allBooks.length} book folder(s)');
      return true;
    } catch (e) {
      _setStatus('Backup failed: $e');
      debugPrint('Drive backup error: $e');
      return false;
    } finally {
      _progress = null;
      _setBusy(false);
    }
  }

  /// Upload [path] into [folderId] unless a file with the same name is already
  /// there. Updates [index] so duplicate references within one run skip too.
  Future<void> _uploadIfMissing(drive.DriveApi api, String folderId,
      Map<String, String> index, String path) async {
    final name = p.basename(path);
    if (index.containsKey(name)) return;
    final f = File(path);
    if (!await f.exists()) return;
    await _uploadFile(api, folderId, name, f);
    index[name] = 'uploaded';
  }

  // ─── Load (pull) ───

  Future<bool> loadCatalog(LibraryStore library,
      {String? folderId, String? folderName}) async {
    final api = await _api();
    if (api == null) {
      _setStatus('Not connected');
      return false;
    }
    _setBusy(true, 'Looking up catalog in Drive…');
    try {
      // Prefer a nested "Metro Sound" subfolder; fall back to the selected
      // folder itself for older flat backups (or if they picked it directly).
      String rootId;
      if (folderId == null) {
        rootId = await _ensureFolder(api, _folderName);
      } else if (folderName == _folderName) {
        rootId = folderId;
      } else {
        rootId =
            await _findFolder(api, _folderName, parentId: folderId) ?? folderId;
      }
      final rootIndex = await _folderIndex(api, rootId);

      final libId = rootIndex[_libraryFile];
      if (libId == null) {
        _setStatus('No catalog found in Drive yet — back up first.');
        return false;
      }

      final libBytes = await _downloadBytes(api, libId);
      final data = jsonDecode(utf8.decode(libBytes)) as Map<String, dynamic>;
      final books = ((data['books'] as List?) ?? [])
          .map((e) => Book.fromJson(e as Map<String, dynamic>))
          .toList();
      final tracks = ((data['tracks'] as List?) ?? [])
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList();

      // Build a file index per book subfolder.
      final subfolders = await _listSubfolders(api, rootId);
      final bookFileIndex = <String, Map<String, String>>{}; // bookId -> name->id
      for (final b in books) {
        final fid = subfolders[_bookFolderName(b)];
        bookFileIndex[b.id] =
            fid != null ? await _folderIndex(api, fid) : <String, String>{};
      }

      // Each download knows which book's folder index to look in.
      final downloads = <(
        Map<String, String> index,
        String name,
        String destDir,
        void Function(String) assign
      )>[];
      for (final t in tracks) {
        final idx = bookFileIndex[t.bookId] ?? const {};
        downloads.add((idx, p.basename(t.audioPath), library.audioDirPath,
            (lp) => t.audioPath = lp));
        for (var i = 0; i < t.photoPaths.length; i++) {
          final pi = i;
          downloads.add((idx, p.basename(t.photoPaths[i]), library.photoDirPath,
              (lp) => t.photoPaths[pi] = lp));
        }
      }
      for (final b in books) {
        if (b.coverPath != null) {
          final idx = bookFileIndex[b.id] ?? const {};
          downloads.add((idx, p.basename(b.coverPath!), library.coverDirPath,
              (lp) => b.coverPath = lp));
        }
      }

      final total = downloads.length;
      var done = 0;
      for (final d in downloads) {
        final fileId = d.$1[d.$2];
        final dest = p.join(d.$3, d.$2);
        if (fileId != null && !await File(dest).exists()) {
          final bytes = await _downloadBytes(api, fileId);
          await File(dest).writeAsBytes(bytes);
        }
        d.$4(dest); // rewrite path to local copy
        done++;
        if (total > 0) {
          _setProgress(done / total, 'Loading catalog… ($done/$total)');
        }
      }

      await library.replaceCatalog(books, tracks);
      _setStatus('Catalog loaded — ${books.length} book(s), ${tracks.length} track(s)');
      return true;
    } catch (e) {
      _setStatus('Load failed: $e');
      debugPrint('Drive load error: $e');
      return false;
    } finally {
      _progress = null;
      _setBusy(false);
    }
  }

  // ─── Drive helpers ───

  /// Find a folder by [name] (optionally under [parentId]) without creating it.
  Future<String?> _findFolder(drive.DriveApi api, String name,
      {String? parentId}) async {
    final q = StringBuffer(
        "mimeType='application/vnd.google-apps.folder' and name='${_escape(name)}' and trashed=false");
    if (parentId != null) q.write(" and '$parentId' in parents");
    final res = await api.files
        .list(q: q.toString(), $fields: 'files(id,name)', spaces: 'drive');
    final found = res.files;
    return (found != null && found.isNotEmpty) ? found.first.id : null;
  }

  /// Resolve the actual data root: a "Metro Sound" folder that holds
  /// library.json and the per-book subfolders. It's always the app folder,
  /// nested inside whatever the user selected:
  ///   • nothing selected        → "Metro Sound" at the Drive root
  ///   • new folder "X"          → "X/Metro Sound"
  ///   • existing folder "X"     → "X/Metro Sound"
  ///   • the "Metro Sound" folder itself → used as-is (no double nesting)
  Future<String> _dataRoot(drive.DriveApi api,
      {String? folderId, String? folderName}) async {
    if (folderId == null && (folderName == null || folderName.trim().isEmpty)) {
      return _ensureFolder(api, _folderName);
    }
    if (folderId == null) {
      final parent = await _ensureFolder(api, folderName!.trim());
      return _ensureFolder(api, _folderName, parentId: parent);
    }
    if (folderName == _folderName) return folderId;
    return _ensureFolder(api, _folderName, parentId: folderId);
  }

  /// Find or create a folder by [name], optionally under [parentId].
  Future<String> _ensureFolder(drive.DriveApi api, String name,
      {String? parentId}) async {
    final q = StringBuffer(
        "mimeType='application/vnd.google-apps.folder' and name='${_escape(name)}' and trashed=false");
    if (parentId != null) q.write(" and '$parentId' in parents");
    final res = await api.files.list(
      q: q.toString(),
      $fields: 'files(id,name)',
      spaces: 'drive',
    );
    final found = res.files;
    if (found != null && found.isNotEmpty) return found.first.id!;
    final folder = drive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder';
    if (parentId != null) folder.parents = [parentId];
    final created = await api.files.create(folder, $fields: 'id');
    return created.id!;
  }

  /// Subfolders directly under [parentId], mapped name -> id.
  Future<Map<String, String>> _listSubfolders(
      drive.DriveApi api, String parentId) async {
    final map = <String, String>{};
    String? pageToken;
    do {
      final res = await api.files.list(
        q: "'$parentId' in parents and "
            "mimeType='application/vnd.google-apps.folder' and trashed=false",
        $fields: 'nextPageToken, files(id,name)',
        pageSize: 1000,
        pageToken: pageToken,
        spaces: 'drive',
      );
      for (final f in res.files ?? const <drive.File>[]) {
        if (f.name != null && f.id != null) map[f.name!] = f.id!;
      }
      pageToken = res.nextPageToken;
    } while (pageToken != null);
    return map;
  }

  String _escape(String s) =>
      s.replaceAll('\\', '\\\\').replaceAll("'", "\\'");

  String _bookFolderName(Book b) =>
      b.title.trim().isEmpty ? 'Untitled' : b.title.trim();

  /// Map of fileName -> fileId for everything (non-trashed) in the folder.
  Future<Map<String, String>> _folderIndex(
      drive.DriveApi api, String folderId) async {
    final map = <String, String>{};
    String? pageToken;
    do {
      final res = await api.files.list(
        q: "'$folderId' in parents and trashed=false",
        $fields: 'nextPageToken, files(id,name)',
        pageSize: 1000,
        pageToken: pageToken,
        spaces: 'drive',
      );
      for (final f in res.files ?? const <drive.File>[]) {
        if (f.name != null && f.id != null) map[f.name!] = f.id!;
      }
      pageToken = res.nextPageToken;
    } while (pageToken != null);
    return map;
  }

  Future<void> _uploadFile(
      drive.DriveApi api, String folderId, String name, File file) async {
    final length = await file.length();
    final media = drive.Media(file.openRead(), length);
    final meta = drive.File()
      ..name = name
      ..parents = [folderId];
    await api.files.create(meta, uploadMedia: media);
  }

  Future<void> _uploadBytes(drive.DriveApi api, String folderId, String name,
      List<int> bytes, String? existingId, String contentType) async {
    final media = drive.Media(
      Stream.value(bytes),
      bytes.length,
      contentType: contentType,
    );
    if (existingId != null) {
      await api.files.update(drive.File(), existingId, uploadMedia: media);
    } else {
      final meta = drive.File()
        ..name = name
        ..parents = [folderId];
      await api.files.create(meta, uploadMedia: media);
    }
  }

  Future<List<int>> _downloadBytes(drive.DriveApi api, String fileId) async {
    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final out = <int>[];
    await for (final chunk in media.stream) {
      out.addAll(chunk);
    }
    return out;
  }

  // ─── Auto-sync (two-way) ───

  /// The catalog snapshot written to Drive: data + tombstones + a signature and
  /// the writer's device id (so peers can tell whose change it is).
  Map<String, dynamic> _catalogPayload(LibraryStore library) => {
        'books': library.allBooks.map((b) => b.toJson()).toList(),
        'tracks': library.allTracks.map((t) => t.toJson()).toList(),
        'deleted': library.tombstones,
        'signature': library.catalogSignature(),
        'writer': _deviceId,
      };

  /// Wire the library into the sync engine. Called once at startup.
  Future<void> attachLibrary(LibraryStore library) async {
    _lib = library;
    await _loadSyncPrefs();
    library.addListener(_onLibraryChanged);
    if (_autoSync && isConnected) {
      _startPoll();
      // Reconcile once on launch: pull anything new, then push local edits.
      unawaited(_syncCycle(initial: true));
    }
  }

  Future<void> setAutoSync(bool on, {String? folderId, String? folderName}) async {
    if (on && !isConnected) {
      _setAutoState('Connect to Google Drive first');
      return;
    }
    _autoSync = on;
    if (on) {
      if (folderId != null) {
        _autoFolderId = folderId;
        _autoFolderName = folderName;
      }
      await _saveSyncPrefs();
      notifyListeners();
      _startPoll();
      await _syncCycle(initial: true);
    } else {
      _stopPoll();
      _debounce?.cancel();
      await _saveSyncPrefs();
      _setAutoState('Auto-sync off');
    }
  }

  void _onLibraryChanged() {
    if (!_autoSync || _inSync) return;
    final lib = _lib;
    if (lib == null) return;
    if (lib.catalogSignature() == _syncedSignature) return; // nothing new
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () {
      unawaited(_syncCycle());
    });
  }

  void _startPoll() {
    _poll?.cancel();
    // Pull cadence is a battery/latency choice, not a Drive-quota one — each
    // idle poll is just a couple of cheap metadata calls.
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_syncCycle());
    });
  }

  void _stopPoll() {
    _poll?.cancel();
    _poll = null;
  }

  /// One reconcile pass: pull remote changes (merge), then push local changes.
  /// Serialised by [_inSync]; failures leave [_pendingPush] set so the next
  /// poll retries (this is what makes offline edits sync when back online).
  Future<void> _syncCycle({bool initial = false}) async {
    final lib = _lib;
    if (lib == null || !_autoSync || _inSync) return;
    final api = await _api();
    if (api == null) {
      _setAutoState('Offline — will retry');
      _pendingPush = true;
      return;
    }
    _inSync = true;
    try {
      final folderId = await _resolveAutoFolder(api);
      _setAutoState('Syncing…');
      await _pullMerge(api, lib, folderId);
      if (lib.catalogSignature() != _syncedSignature || _pendingPush || initial) {
        await _pushCatalog(api, lib, folderId);
      }
      _pendingPush = false;
      _setAutoState('Synced');
    } catch (e) {
      _pendingPush = true;
      _setAutoState('Offline — will retry');
      debugPrint('Auto-sync error: $e');
    } finally {
      _inSync = false;
    }
  }

  Future<String> _resolveAutoFolder(drive.DriveApi api) async {
    if (_autoFolderId != null) return _autoFolderId!;
    final id = await _ensureFolder(api, _folderName);
    _autoFolderId = id;
    _autoFolderName = _folderName;
    await _saveSyncPrefs();
    return id;
  }

  /// Upload the catalog + any missing media to the auto-sync folder (silent —
  /// no big progress UI).
  Future<void> _pushCatalog(
      drive.DriveApi api, LibraryStore library, String rootId) async {
    if (library.allBooks.isEmpty && library.allTracks.isEmpty) return;
    final sig = library.catalogSignature();
    final rootIndex = await _folderIndex(api, rootId);
    await _uploadBytes(api, rootId, _libraryFile,
        utf8.encode(jsonEncode(_catalogPayload(library))), rootIndex[_libraryFile],
        'application/json');

    // Only walk the per-book folders to upload media when there's media we
    // haven't uploaded yet — a metadata-only edit (done, BPM…) skips it, so the
    // common case is just the tiny library.json upload above.
    final mediaNames = <String>{
      for (final b in library.allBooks)
        if (b.coverPath != null) p.basename(b.coverPath!),
      for (final t in library.allTracks) ...[
        p.basename(t.audioPath),
        for (final ph in t.photoPaths) p.basename(ph),
      ],
    };
    if (mediaNames.difference(_uploadedMedia).isNotEmpty) {
      for (final b in library.allBooks) {
        final bookFolderId =
            await _ensureFolder(api, _bookFolderName(b), parentId: rootId);
        final bookIndex = await _folderIndex(api, bookFolderId);
        if (b.coverPath != null) {
          await _uploadIfMissing(api, bookFolderId, bookIndex, b.coverPath!);
        }
        for (final t in library.allTracks.where((t) => t.bookId == b.id)) {
          await _uploadIfMissing(api, bookFolderId, bookIndex, t.audioPath);
          for (final ph in t.photoPaths) {
            await _uploadIfMissing(api, bookFolderId, bookIndex, ph);
          }
        }
      }
      _uploadedMedia
        ..clear()
        ..addAll(mediaNames);
    }
    _syncedSignature = sig;
    _lastSeenRemoteSig = sig; // our own push — don't pull it back
    await _saveSyncPrefs();
  }

  /// Download the remote catalog and merge it into the local library, pulling
  /// any new/updated media first.
  Future<void> _pullMerge(
      drive.DriveApi api, LibraryStore library, String rootId) async {
    final rootIndex = await _folderIndex(api, rootId);
    final libId = rootIndex[_libraryFile];
    if (libId == null) return; // nothing on Drive yet

    // Cheap metadata check first — skip the full download when the remote
    // catalog hasn't changed since we last looked.
    final meta =
        await api.files.get(libId, $fields: 'modifiedTime') as drive.File;
    final mtime = meta.modifiedTime?.toUtc().toIso8601String() ?? '';
    if (mtime.isNotEmpty && mtime == _remoteMtime) return;

    final data = jsonDecode(utf8.decode(await _downloadBytes(api, libId)))
        as Map<String, dynamic>;
    _remoteMtime = mtime; // we've now seen this version
    final remoteSig = (data['signature'] as num?)?.toInt() ?? 0;
    if (remoteSig == _lastSeenRemoteSig) {
      await _saveSyncPrefs();
      return; // already processed (often our own push)
    }

    final remoteBooks = ((data['books'] as List?) ?? [])
        .map((e) => Book.fromJson(e as Map<String, dynamic>))
        .toList();
    final remoteTracks = ((data['tracks'] as List?) ?? [])
        .map((e) => Track.fromJson(e as Map<String, dynamic>))
        .toList();
    final remoteDeleted = ((data['deleted'] as Map?) ?? {})
        .map((k, v) => MapEntry(k as String, (v as num).toInt()));

    // Index each book subfolder so we can fetch media by filename.
    final subfolders = await _listSubfolders(api, rootId);
    final bookIndex = <String, Map<String, String>>{};
    for (final b in remoteBooks) {
      final fid = subfolders[_bookFolderName(b)];
      bookIndex[b.id] =
          fid != null ? await _folderIndex(api, fid) : <String, String>{};
    }

    final localBooks = {for (final b in library.allBooks) b.id: b};
    final localTracks = {for (final t in library.allTracks) t.id: t};

    // Download media only for entities that are new or newer than ours.
    for (final t in remoteTracks) {
      final lt = localTracks[t.id];
      if (lt != null && lt.updatedAt >= t.updatedAt) continue;
      final idx = bookIndex[t.bookId] ?? const {};
      t.audioPath = await _fetchInto(
          api, idx, p.basename(t.audioPath), library.audioDirPath);
      for (var i = 0; i < t.photoPaths.length; i++) {
        t.photoPaths[i] = await _fetchInto(
            api, idx, p.basename(t.photoPaths[i]), library.photoDirPath);
      }
    }
    for (final b in remoteBooks) {
      if (b.coverPath == null) continue;
      final lb = localBooks[b.id];
      if (lb != null && lb.updatedAt >= b.updatedAt) continue;
      final idx = bookIndex[b.id] ?? const {};
      b.coverPath = await _fetchInto(
          api, idx, p.basename(b.coverPath!), library.coverDirPath);
    }

    await library.mergeRemote(remoteBooks, remoteTracks, remoteDeleted);
    _lastSeenRemoteSig = remoteSig;
    if (library.catalogSignature() == remoteSig) {
      _syncedSignature = remoteSig; // fully converged
    }
    await _saveSyncPrefs();
  }

  /// Download [name] from [index] into [destDir] (skips if already present);
  /// returns the local path.
  Future<String> _fetchInto(drive.DriveApi api, Map<String, String> index,
      String name, String destDir) async {
    final dest = p.join(destDir, name);
    final fileId = index[name];
    if (fileId != null && !await File(dest).exists()) {
      await File(dest).writeAsBytes(await _downloadBytes(api, fileId));
    }
    return dest;
  }

  void _setAutoState(String s) {
    _autoState = s;
    notifyListeners();
  }

  Future<void> _loadSyncPrefs() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _syncPrefsFile = File(p.join(dir.path, 'sync.json'));
      if (await _syncPrefsFile!.exists()) {
        final j = jsonDecode(await _syncPrefsFile!.readAsString())
            as Map<String, dynamic>;
        _autoSync = j['autoSync'] == true;
        _autoFolderId = j['folderId'] as String?;
        _autoFolderName = j['folderName'] as String?;
        _deviceId = (j['deviceId'] as String?) ?? '';
        _syncedSignature = (j['syncedSig'] as num?)?.toInt() ?? 0;
        _lastSeenRemoteSig = (j['remoteSig'] as num?)?.toInt() ?? 0;
        _remoteMtime = (j['remoteMtime'] as String?) ?? '';
        _uploadedMedia
          ..clear()
          ..addAll(((j['uploadedMedia'] as List?) ?? []).cast<String>());
      }
    } catch (e) {
      debugPrint('Sync prefs load error: $e');
    }
    if (_deviceId.isEmpty) {
      _deviceId =
          'd${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
      await _saveSyncPrefs();
    }
  }

  Future<void> _saveSyncPrefs() async {
    try {
      await _syncPrefsFile?.writeAsString(jsonEncode({
        'autoSync': _autoSync,
        'folderId': _autoFolderId,
        'folderName': _autoFolderName,
        'deviceId': _deviceId,
        'syncedSig': _syncedSignature,
        'remoteSig': _lastSeenRemoteSig,
        'remoteMtime': _remoteMtime,
        'uploadedMedia': _uploadedMedia.toList(),
      }));
    } catch (_) {}
  }

  // ─── Credential persistence ───

  Future<void> _saveCreds() async {
    final c = _creds;
    if (c == null) return;
    final json = {
      'accessToken': {
        'type': c.accessToken.type,
        'data': c.accessToken.data,
        'expiry': c.accessToken.expiry.toIso8601String(),
      },
      'refreshToken': c.refreshToken,
      'idToken': c.idToken,
      'scopes': c.scopes,
    };
    await _credsFile.writeAsString(jsonEncode(json));
  }

  Future<void> _loadCreds() async {
    try {
      if (!await _credsFile.exists()) return;
      final j = jsonDecode(await _credsFile.readAsString()) as Map<String, dynamic>;
      final at = j['accessToken'] as Map<String, dynamic>;
      _creds = AccessCredentials(
        AccessToken(
          at['type'] as String,
          at['data'] as String,
          DateTime.parse(at['expiry'] as String).toUtc(),
        ),
        j['refreshToken'] as String?,
        ((j['scopes'] as List?) ?? _scopes).map((e) => e as String).toList(),
        idToken: j['idToken'] as String?,
      );
    } catch (e) {
      debugPrint('loadCreds error: $e');
    }
  }

  // ─── State plumbing ───

  void _setBusy(bool v, [String? status]) {
    _busy = v;
    if (status != null) _status = status;
    if (!v) _progress = null;
    notifyListeners();
  }

  void _setStatus(String s) {
    _status = s;
    notifyListeners();
  }

  void _setProgress(double v, String s) {
    _progress = v;
    _status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _poll?.cancel();
    _lib?.removeListener(_onLibraryChanged);
    _authClient?.close();
    _baseClient.close();
    super.dispose();
  }
}
