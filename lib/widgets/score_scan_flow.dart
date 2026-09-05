import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../services/library_store.dart';
import '../services/musicxml.dart';
import '../services/pro.dart';
import '../services/score_reader.dart';
import '../services/score_synth.dart';
import '../ui/studio.dart';
import 'pro_sheet.dart';

/// "Scan a score": photograph (or pick) a page of sheet music, have the score
/// reader transcribe it, and land a synthesized practice track — with the
/// photo attached as its practice sheet and a matching metronome preset — in
/// the "From Score" book.
Future<void> runScoreScanFlow(BuildContext context) async {
  showStudioMenu(
    context,
    title: 'Scan a score',
    actions: [
      StudioMenuAction(
        'Take a photo',
        icon: Icons.photo_camera_outlined,
        onTap: () => _scanFrom(context, ImageSource.camera),
      ),
      StudioMenuAction(
        'Choose from library',
        icon: Icons.photo_library_outlined,
        onTap: () => _scanFrom(context, ImageSource.gallery),
      ),
    ],
  );
}

Future<void> _scanFrom(BuildContext context, ImageSource source) async {
  final XFile? shot;
  try {
    // Capped size keeps the upload small and well under API limits.
    shot = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 88,
    );
  } catch (_) {
    // e.g. no camera on this device — fall back to the library picker.
    if (source == ImageSource.camera && context.mounted) {
      await _scanFrom(context, ImageSource.gallery);
    }
    return;
  }
  if (shot == null || !context.mounted) return;

  final apiKey = await _ensureApiKey(context);
  if (apiKey == null || !context.mounted) return;

  // Progress dialog while the model studies the page (tens of seconds).
  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Studio.barrier,
    builder: (_) => const _ReadingDialog(),
  );
  Score? score;
  Object? error;
  try {
    score = await ScoreReader.readPhoto(File(shot.path), apiKey: apiKey);
  } catch (e) {
    error = e;
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();

  if (score == null) {
    showToast(
      context,
      error is ScoreReaderException || error is MusicXmlException
          ? '$error'
          : 'Score reading failed: $error',
    );
    return;
  }
  await addScoreTrack(
    context,
    score,
    bookTitle: 'From Score',
    photoPath: shot.path,
  );
}

/// The user's Anthropic API key, prompting for it (and storing it in the
/// keychain) the first time. Returns null if the user cancels.
Future<String?> _ensureApiKey(BuildContext context) async {
  final existing = await ScoreReader.storedApiKey();
  if (existing != null) return existing;
  if (!context.mounted) return null;
  final entered = await studioPrompt(
    context,
    title: 'Anthropic API key',
    hint: 'sk-ant-… (scanning uses your own key)',
  );
  if (entered == null || entered.trim().isEmpty) return null;
  await ScoreReader.saveApiKey(entered);
  return entered.trim();
}

/// Shared final stage of every score→track path (scan, MusicXML import, demo
/// score): prompt for the tempo, synthesize the WAV on the exact beat grid,
/// import it into [bookTitle] with the score's metronome preset, and attach
/// [photoPath] as the track's practice photo when given.
Future<bool> addScoreTrack(
  BuildContext context,
  Score score, {
  required String bookTitle,
  String? photoPath,
}) async {
  final entered = await studioPrompt(
    context,
    title: 'Tempo (BPM)',
    initial: '${score.bpm}',
    hint: 'Marked tempo: ${score.bpm}',
  );
  if (entered == null || !context.mounted) return false;
  final bpm = (int.tryParse(entered.trim()) ?? score.bpm).clamp(20, 300);

  final library = context.read<LibraryStore>();
  final pro = context.read<Pro>();
  try {
    final existing = library.books.where((b) => b.title == bookTitle);
    if (existing.isEmpty &&
        !pro.isPro &&
        library.books.length >= Pro.freeBookLimit) {
      showProSheet(
        context,
        reason: '${Pro.freeLibraryLimitText} '
            'Unlock Pro for an unlimited library.',
      );
      return false;
    }
    final book = existing.isEmpty
        ? await library.createBook(bookTitle)
        : existing.first;

    final tmp = await getTemporaryDirectory();
    final safe = score.title.replaceAll(RegExp(r'[^\w\- ()]'), '').trim();
    final f = File(p.join(tmp.path, '${safe.isEmpty ? 'Score' : safe}.wav'));
    await f.writeAsBytes(renderScoreWav(score, bpm: bpm));
    await library.importAudioFiles(book.id, [f.path]);

    final track = library.tracksForBook(book.id).last;
    track
      ..bpm = bpm
      ..beatsPerBar = score.beatsPerBar
      ..timeSigDenominator = score.denominator
      ..metronomeOn = true;
    await library.updateTrack(track);
    if (photoPath != null) await library.addPhoto(track, photoPath);

    try {
      await f.delete();
    } catch (_) {}
    if (context.mounted) {
      showToast(context,
          'Added "${track.title}" to "$bookTitle" at $bpm BPM — play it with '
          'the metronome locked.');
    }
    return true;
  } catch (e) {
    if (context.mounted) showToast(context, 'Could not add the track: $e');
    return false;
  }
}

class _ReadingDialog extends StatelessWidget {
  const _ReadingDialog();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: StudioCard(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Studio.amber),
              const SizedBox(height: 16),
              Text('Reading the score…', style: Studio.title),
              const SizedBox(height: 4),
              Text(
                'Transcribing the notation — this can take a minute.',
                style: Studio.bodyDim,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
