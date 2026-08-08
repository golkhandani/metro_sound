import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// On-device data cleanup used by the (test-build-only) Advanced settings page.
///
/// The app keeps everything under the application-support directory
/// (`audio/`, `photos/`, `covers/`, `library.json`, `settings.json`,
/// `metronome.json`) and stages transient work in the temporary directory. Pro
/// entitlement lives in the Keychain and is intentionally NOT touched here —
/// resetting the purchase is a separate action ([Pro.resetPurchaseLocal]).
class AppReset {
  /// Delete everything in the temporary/cache directory. Non-destructive to the
  /// user's library. Returns the number of bytes freed.
  static Future<int> clearCache() async {
    final tmp = await getTemporaryDirectory();
    return _deleteChildren(tmp);
  }

  /// Factory reset of on-device content and state: imported audio, sheet photos,
  /// book covers, recordings, the library catalog, and app/metronome settings,
  /// plus the cache. Does NOT clear the Keychain (Pro), so a paid user stays
  /// Pro. A relaunch is needed afterwards for a fully clean in-memory state.
  static Future<void> eraseAllData() async {
    for (final dir in await Future.wait([
      getApplicationSupportDirectory(),
      getTemporaryDirectory(),
      getApplicationDocumentsDirectory(),
    ])) {
      await _deleteChildren(dir);
    }
  }

  static Future<int> _deleteChildren(Directory dir) async {
    var freed = 0;
    if (!await dir.exists()) return freed;
    await for (final entity in dir.list()) {
      try {
        if (entity is File) {
          freed += await entity.length();
          await entity.delete();
        } else if (entity is Directory) {
          freed += await _dirSize(entity);
          await entity.delete(recursive: true);
        }
      } catch (_) {
        // Skip anything locked/open; best-effort cleanup.
      }
    }
    return freed;
  }

  static Future<int> _dirSize(Directory dir) async {
    var size = 0;
    try {
      await for (final e in dir.list(recursive: true)) {
        if (e is File) size += await e.length();
      }
    } catch (_) {}
    return size;
  }
}
