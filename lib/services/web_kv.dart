import 'package:shared_preferences/shared_preferences.dart';

/// Tiny string key/value store backed by SharedPreferences. Used on web (where
/// there's no filesystem) to persist the small JSON documents the services
/// would otherwise write to files. Native keeps using files.
class WebKv {
  static SharedPreferences? _prefs;

  static Future<void> ensure() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static String? read(String key) => _prefs?.getString(key);

  static Future<void> write(String key, String value) async {
    await _prefs?.setString(key, value);
  }
}
