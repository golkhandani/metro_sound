import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'library_store.dart';
import 'settings.dart';

/// Seeds a small "Getting Started" book on the very first launch so new users
/// never face an empty library (and the tutorial has real things to point at).
/// Runs once per install — deleting the book does NOT bring it back.
class SampleLibrary {
  static Future<void> seedIfNeeded(
      LibraryStore library, AppSettings settings) async {
    if (settings.sampleSeeded) return;
    // Never overwrite real content (e.g. restored from a backup/import).
    if (library.books.isNotEmpty) {
      await settings.setSampleSeeded(true);
      return;
    }

    try {
      final tmp = await getTemporaryDirectory();
      final dir = await Directory(p.join(tmp.path, 'sample_seed'))
          .create(recursive: true);

      // (title, melody root midi note, seconds, bpm)
      const tracks = [
        ('Welcome — tap me to play', 57, 24, 90), // A3
        ('Lock the metronome to me', 60, 28, 96), // C4
        ('Practice me slowly (speed)', 62, 26, 80), // D4
        ('Mark me as done', 64, 22, 104), // E4
        ('Share this book with a friend', 55, 30, 100), // G3
      ];

      final paths = <String>[];
      for (var i = 0; i < tracks.length; i++) {
        final (title, root, secs, _) = tracks[i];
        final f = File(p.join(dir.path, '${i + 1}-$title.wav'));
        f.writeAsBytesSync(demoWav(rootMidi: root, seconds: secs, seed: i));
        paths.add(f.path);
      }

      final book = await library.createBook('Getting Started');
      await library.importAudioFiles(book.id, paths);

      final imported = library.tracksForBook(book.id);
      for (var i = 0; i < imported.length && i < tracks.length; i++) {
        imported[i]
          ..bpm = tracks[i].$4
          ..done = i == 0; // one finished track shows the progress UI
        await library.updateTrack(imported[i]);
      }

      // Clean the temp copies (importAudioFiles copied them into app storage).
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    } catch (_) {
      // Seeding is best-effort; an empty library is not an error.
    }
    await settings.setSampleSeeded(true);
  }
}

/// Synthesizes a gentle plucked-tone melody as a 16-bit mono WAV — pleasant
/// enough to demo the player/metronome without bundling audio assets.
/// Also used by the (dev-only) screenshot rig.
Uint8List demoWav({int rootMidi = 57, int seconds = 24, int seed = 0}) {
  const rate = 22050;
  final n = rate * seconds;
  final data = ByteData(44 + n * 2);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + n * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, n * 2, Endian.little);

  // A slow arpeggio over a minor-ish pentatonic shape, one note per beat,
  // each with a plucked exponential decay. Varies a little by [seed].
  const steps = [0, 3, 7, 12, 7, 3]; // semitones above the root
  final noteLen = rate ~/ 2; // two notes per second
  double freq(int midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

  for (var i = 0; i < n; i++) {
    final note = (i ~/ noteLen);
    final step = steps[(note + seed) % steps.length];
    final f = freq(rootMidi + step);
    final tIn = (i % noteLen) / rate;
    final env = math.exp(-tIn * 5); // pluck decay
    final s = math.sin(2 * math.pi * f * (i / rate)) * env;
    // Soft second harmonic for warmth.
    final h = math.sin(4 * math.pi * f * (i / rate)) * env * 0.25;
    data.setInt16(44 + i * 2, ((s + h) * 5500).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}
