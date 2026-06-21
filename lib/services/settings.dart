import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum NoteNaming { letters, solfege }

enum Accidental { flats, sharps, both }

/// Small app-wide preferences, persisted to a JSON file (no extra plugin).
class AppSettings extends ChangeNotifier {
  // Base 12 chromatic names (C = index 0).
  static const _lettersFlat = [
    'C', 'D♭', 'D', 'E♭', 'E', 'F', 'G♭', 'G', 'A♭', 'A', 'B♭', 'B'
  ];
  static const _lettersSharp = [
    'C', 'C♯', 'D', 'D♯', 'E', 'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B'
  ];
  static const _solfegeFlat = [
    'Do', 'Re♭', 'Re', 'Mi♭', 'Mi', 'Fa', 'Sol♭', 'Sol', 'La♭', 'La', 'Si♭', 'Si'
  ];
  static const _solfegeSharp = [
    'Do', 'Do♯', 'Re', 'Re♯', 'Mi', 'Fa', 'Fa♯', 'Sol', 'Sol♯', 'La', 'La♯', 'Si'
  ];

  // Quarter-tone (Persian) mapping: odd 24-TET index -> (natural chromatic
  // index, suffix). koron = quarter-flat, sori = quarter-sharp.
  static const Map<int, (int, String)> _micro = {
    1: (0, 'sori'), // Do sori
    3: (2, 'koron'), // Re koron
    5: (2, 'sori'), // Re sori
    7: (4, 'koron'), // Mi koron
    9: (5, 'koron'), // Fa koron
    11: (5, 'sori'), // Fa sori
    13: (7, 'koron'), // Sol koron
    15: (7, 'sori'), // Sol sori
    17: (9, 'koron'), // La koron
    19: (9, 'sori'), // La sori
    21: (11, 'koron'), // Si koron
    23: (0, 'koron'), // Do koron
  };

  NoteNaming _noteNaming = NoteNaming.letters;
  NoteNaming get noteNaming => _noteNaming;

  Accidental _accidental = Accidental.flats;
  Accidental get accidental => _accidental;

  bool _microtones = false;
  bool get microtones => _microtones;

  /// Quarter-tone divisions if microtones on (24), else 12.
  int get divisions => _microtones ? 24 : 12;

  File? _file;

  Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File(p.join(dir.path, 'settings.json'));
      if (await _file!.exists()) {
        final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        if (j['noteNaming'] == 'solfege') _noteNaming = NoteNaming.solfege;
        switch (j['accidental']) {
          case 'sharps':
            _accidental = Accidental.sharps;
          case 'both':
            _accidental = Accidental.both;
          default:
            _accidental = Accidental.flats;
        }
        _microtones = j['microtones'] == true;
      }
    } catch (e) {
      debugPrint('Settings load error: $e');
    }
  }

  Future<void> _save() async {
    try {
      await _file?.writeAsString(jsonEncode({
        'noteNaming': _noteNaming == NoteNaming.solfege ? 'solfege' : 'letters',
        'accidental': _accidental.name,
        'microtones': _microtones,
      }));
    } catch (_) {}
  }

  Future<void> setNoteNaming(NoteNaming n) async {
    if (n == _noteNaming) return;
    _noteNaming = n;
    notifyListeners();
    await _save();
  }

  Future<void> setAccidental(Accidental a) async {
    if (a == _accidental) return;
    _accidental = a;
    notifyListeners();
    await _save();
  }

  Future<void> setMicrotones(bool v) async {
    if (v == _microtones) return;
    _microtones = v;
    notifyListeners();
    await _save();
  }

  List<String> get _flatTable =>
      _noteNaming == NoteNaming.solfege ? _solfegeFlat : _lettersFlat;
  List<String> get _sharpTable =>
      _noteNaming == NoteNaming.solfege ? _solfegeSharp : _lettersSharp;

  /// Name for a chromatic semitone (0–11).
  String _name12(int i) {
    i %= 12;
    final flat = _flatTable[i];
    final sharp = _sharpTable[i];
    if (flat == sharp) return flat; // natural note
    switch (_accidental) {
      case Accidental.flats:
        return flat;
      case Accidental.sharps:
        return sharp;
      case Accidental.both:
        return '$sharp/$flat';
    }
  }

  /// Name for a pitch index in the current division system (12 or 24).
  /// −1 means nothing detected.
  String noteName(int index) {
    if (index < 0) return '–';
    if (!_microtones) return _name12(index);
    if (index.isEven) return _name12(index ~/ 2);
    final (nat, suffix) = _micro[index % 24]!;
    return '${_flatTable[nat]} $suffix'; // natural note has no accidental
  }
}
