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
    } catch (e) {
      _setStatus('Sign-in failed: $e');
      debugPrint('Drive connect error: $e');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> disconnect() async {
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
      final rootId = folderId ??
          await _ensureFolder(
              api,
              (folderName != null && folderName.trim().isNotEmpty)
                  ? folderName.trim()
                  : _folderName);
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
      final libraryJson = jsonEncode({
        'books': library.allBooks.map((b) => b.toJson()).toList(),
        'tracks': library.allTracks.map((t) => t.toJson()).toList(),
      });
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

  Future<bool> loadCatalog(LibraryStore library, {String? folderId}) async {
    final api = await _api();
    if (api == null) {
      _setStatus('Not connected');
      return false;
    }
    _setBusy(true, 'Looking up catalog in Drive…');
    try {
      final rootId = folderId ?? await _ensureFolder(api, _folderName);
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
    _authClient?.close();
    _baseClient.close();
    super.dispose();
  }
}
