import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../screens/book_screen.dart';
import '../screens/player_screen.dart';
import '../services/audio_controller.dart';
import '../services/library_store.dart';
import '../services/sample_library.dart';
import '../services/metronome.dart';
import '../services/settings.dart';
import '../widgets/package_job_overlay.dart';

/// Dev-only App Store screenshot rig. Entirely inert unless built with
/// `--dart-define=SHOT=<screen>`; seeds demo content and auto-navigates so a
/// simulator screenshot can be captured. Never active in store builds.
///
/// SHOT values: onboarding | library | book | player | metronome | tuner |
/// settings. Add THEME=light for the light skin.
class ScreenshotDirector {
  static const shot = String.fromEnvironment('SHOT');
  static const theme = String.fromEnvironment('THEME');
  static bool get active => shot.isNotEmpty;

  /// Initial tab for tab-based shots.
  static int? get initialTab => switch (shot) {
        'metronome' => 1,
        'tuner' => 2,
        'settings' => 3,
        _ => null,
      };

  static Future<void> prepare(
      LibraryStore library, AppSettings settings) async {
    if (!active) return;
    await settings.setSampleSeeded(true); // rig content replaces the starter
    // Deterministic skin per shot (dark is the brand default).
    await settings.setThemeMode(theme == 'light' ? 'light' : 'dark');
    if (shot == 'onboarding') {
      await settings.setOnboardingDone(false);
      return;
    }
    await settings.setOnboardingDone(true);
    for (final id in [
      'library', 'metronome', 'tuner', 'settings', 'book', 'player',
    ]) {
      await settings.markTipSeen(id);
    }
    if (library.books.isNotEmpty) return; // already seeded
    await _seed(library);
  }

  /// Post-launch navigation for pushed-route shots + scene dressing.
  static void direct(BuildContext context) {
    if (!active) return;
    final library = context.read<LibraryStore>();
    switch (shot) {
      case 'metronome':
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => context.read<Metronome>().start());
      case 'book':
        final book = library.books.first;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          appNavigatorKey.currentState!
              .push(MaterialPageRoute(builder: (_) => BookScreen(book: book)));
        });
      case 'player':
        final book = library.books.first;
        final tracks = library.tracksForBook(book.id);
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final audio = appNavigatorKey.currentContext!.read<AudioController>();
          audio.openQueue(tracks, 1);
          appNavigatorKey.currentState!.push(
              MaterialPageRoute(builder: (_) => const PlayerScreen()));
          await Future.delayed(const Duration(milliseconds: 600));
          audio.play();
        });
    }
  }

  // ─── Demo content ───

  static Future<void> _seed(LibraryStore library) async {
    final tmp = await getTemporaryDirectory();
    final dir =
        await Directory(p.join(tmp.path, 'shot_seed')).create(recursive: true);

    Future<void> book(String title, List<String> tracks,
        {int done = 0, int bpm = 96}) async {
      final b = await library.createBook(title);
      final paths = <String>[];
      for (var i = 0; i < tracks.length; i++) {
        final f = File(p.join(dir.path, '${i + 1}-${tracks[i]}.wav'));
        if (!f.existsSync()) {
          f.writeAsBytesSync(demoWav(
              rootMidi: 55 + (i * 5) % 12,
              seconds: 40 + (i * 17) % 80,
              seed: i));
        }
        paths.add(f.path);
      }
      await library.importAudioFiles(b.id, paths);
      final imported = library.tracksForBook(b.id);
      for (var i = 0; i < imported.length; i++) {
        imported[i]
          ..done = i < done
          ..bpm = bpm + i * 4;
        await library.updateTrack(imported[i]);
      }
    }

    await book('Ketab-e Avval — Tār',
        ['Darāmad', 'Chahārmezrāb', 'Gushe-ye Kereshmeh', 'Zarbi-e Mahour',
         'Forud', 'Reng-e Shahrāshub', 'Morādkhāni'],
        done: 4, bpm: 88);
    await book('Radif — Māhur',
        ['Darāmad-e Avval', 'Dād', 'Majles Afruz', 'Khosravāni', 'Delkash',
         'Shekaste', 'Neyriz', 'Sāghi Nāme', 'Rāk'],
        done: 3, bpm: 72);
    await book('Violin Method · Book 2',
        ['Open String Etude', 'First Position Study', 'Vibrato Exercise',
         'Bowing Patterns', 'Scale Routine', 'Recital Piece'],
        done: 6, bpm: 104);
    await book('Guitar Etudes',
        ['Arpeggio Study', 'Tremolo', 'Legato Lines', 'Rasgueado', 'Barre Drill'],
        done: 1, bpm: 112);
    await book('Santoor Basics',
        ['Mezrab Control', 'Dast-e Rāst', 'Simple Reng', 'Chahārmezrāb Study'],
        done: 0, bpm: 92);
  }

}
