import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'musicxml.dart';
import 'score_synth.dart';

/// Photo-of-a-score → [Score], via Claude's vision API (the "OMR" stage of the
/// score→audio pipeline). The model transcribes the photographed notation into
/// MusicXML, which the existing [parseMusicXml] turns into a playable Score.
///
/// Uses the user's own Anthropic API key, entered once and kept in the
/// platform keychain via flutter_secure_storage. Raw HTTP because Dart has no
/// official Anthropic SDK.
class ScoreReaderException implements Exception {
  final String message;
  ScoreReaderException(this.message);
  @override
  String toString() => message;
}

class ScoreReader {
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'anthropic_api_key';

  static Future<String?> storedApiKey() async {
    try {
      final v = await _storage.read(key: _keyName);
      if (v != null && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    const fromEnv = String.fromEnvironment('ANTHROPIC_API_KEY');
    return fromEnv.isEmpty ? null : fromEnv;
  }

  static Future<void> saveApiKey(String key) =>
      _storage.write(key: _keyName, value: key.trim());

  static const _prompt =
      'Transcribe the sheet music in this photo into MusicXML '
      '(score-partwise). The music is monophonic — a single melodic line on '
      'one staff. Include the time signature, and the tempo marking as '
      '<sound tempo="..."/> if one is printed. Use exactly one part. If the '
      'notation uses Persian microtonal accidentals (koron/sori), approximate '
      'each to the nearest semitone. Output ONLY the MusicXML document — no '
      'commentary, no code fences.';

  /// Read one photographed page into a [Score]. Slow (the model studies the
  /// image) — expect tens of seconds; run behind a progress indicator.
  static Future<Score> readPhoto(File photo, {required String apiKey}) async {
    final bytes = await photo.readAsBytes();
    if (bytes.length > 4 * 1024 * 1024) {
      throw ScoreReaderException(
          'The photo is too large — try again (the camera flow captures at a '
          'reduced size).');
    }
    final mediaType = switch (p.extension(photo.path).toLowerCase()) {
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      _ => 'image/jpeg',
    };

    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('https://api.anthropic.com/v1/messages'),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
              'anthropic-beta': 'server-side-fallback-2026-07-01',
            },
            body: jsonEncode({
              'model': 'claude-opus-5',
              'max_tokens': 16000,
              // On a safety decline, retry server-side on a fallback model
              // instead of returning nothing.
              'fallbacks': 'default',
              'messages': [
                {
                  'role': 'user',
                  'content': [
                    {
                      'type': 'image',
                      'source': {
                        'type': 'base64',
                        'media_type': mediaType,
                        'data': base64Encode(bytes),
                      },
                    },
                    {'type': 'text', 'text': _prompt},
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(minutes: 5));
    } on SocketException {
      throw ScoreReaderException('No internet connection.');
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ScoreReaderException('Unexpected reply from the score reader.');
    }
    if (res.statusCode == 401) {
      throw ScoreReaderException(
          'The API key was rejected — check it in the key prompt (long-press '
          'Scan a score to re-enter).');
    }
    if (res.statusCode != 200) {
      final msg = (json['error'] as Map<String, dynamic>?)?['message'];
      throw ScoreReaderException('Score reading failed: ${msg ?? res.body}');
    }
    if (json['stop_reason'] == 'refusal') {
      throw ScoreReaderException(
          'The reader declined this image — try a clearer photo of just the '
          'score.');
    }

    final text = ((json['content'] as List?) ?? [])
        .whereType<Map<String, dynamic>>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String? ?? '')
        .join();
    final start = text.indexOf('<score-partwise');
    final end = text.lastIndexOf('</score-partwise>');
    if (start < 0 || end < 0) {
      throw ScoreReaderException(
          'Could not read notation in this photo — try a straighter, '
          'better-lit shot.');
    }
    return parseMusicXml(
      '<?xml version="1.0"?>\n${text.substring(start, end + '</score-partwise>'.length)}',
      fallbackTitle: 'Scanned score',
    );
  }
}
