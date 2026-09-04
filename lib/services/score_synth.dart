import 'dart:math' as math;
import 'dart:typed_data';

/// Score → audio spike for the "photograph the exercise, get a practice track
/// with a synced metronome" idea (see PLAN.md M6 / the OMR discussion).
///
/// A [Score] is the symbolic form an OMR pipeline would produce — the model
/// maps 1:1 onto monophonic MusicXML (pitch step/octave/alter → [ScoreNote.midi],
/// duration/divisions → [ScoreNote.beats]), so a MusicXML importer can slot in
/// later without touching the renderer. [renderScoreWav] synthesizes the score
/// as a plucked-string WAV laid on an exact beat grid: sample 0 is beat 1, every
/// note lands at `beatPos * 60/bpm` seconds. Played as a normal track with the
/// metronome in lock-to-music mode, click and notes cannot drift — both derive
/// from the same grid.

/// One note (or rest) in a monophonic score. [beats] is the length in beats of
/// the time signature's denominator (quarter = 1.0 in x/4, eighth = 0.5, …).
class ScoreNote {
  /// MIDI note number; null is a rest.
  final int? midi;
  final double beats;
  const ScoreNote(this.midi, this.beats);
  const ScoreNote.rest(this.beats) : midi = null;
}

class Score {
  final String title;
  final int bpm;
  final int beatsPerBar;
  final int denominator;
  final List<ScoreNote> notes;
  const Score({
    required this.title,
    required this.bpm,
    required this.beatsPerBar,
    required this.denominator,
    required this.notes,
  });

  double get totalBeats =>
      notes.fold(0.0, (sum, n) => sum + n.beats);
}

/// A hand-transcribed stand-in for a Book One-style beginner exercise: an
/// 8-bar stepwise study in 2/4, played twice. Placeholder until real pages are
/// transcribed (or read by OMR).
const Score sampleScore = Score(
  title: 'Exercise 1 (from score)',
  bpm: 70,
  beatsPerBar: 2,
  denominator: 4,
  notes: [
    // q = 1 beat, e = 0.5 — two four-bar phrases, ascending then answering.
    ScoreNote(60, 1), ScoreNote(60, 1), //  C4 C4
    ScoreNote(62, 1), ScoreNote(62, 1), //  D4 D4
    ScoreNote(64, 1), ScoreNote(62, 1), //  E4 D4
    ScoreNote(60, 2), //                    C4 (half)
    ScoreNote(60, 1), ScoreNote(62, 0.5), ScoreNote(64, 0.5), // C4 D4 E4
    ScoreNote(65, 1), ScoreNote(64, 0.5), ScoreNote(62, 0.5), // F4 E4 D4
    ScoreNote(64, 1), ScoreNote(62, 1), //  E4 D4
    ScoreNote(60, 2), //                    C4 (half)
    // repeat
    ScoreNote(60, 1), ScoreNote(60, 1),
    ScoreNote(62, 1), ScoreNote(62, 1),
    ScoreNote(64, 1), ScoreNote(62, 1),
    ScoreNote(60, 2),
    ScoreNote(60, 1), ScoreNote(62, 0.5), ScoreNote(64, 0.5),
    ScoreNote(65, 1), ScoreNote(64, 0.5), ScoreNote(62, 0.5),
    ScoreNote(64, 1), ScoreNote(62, 1),
    ScoreNote(60, 2),
  ],
);

/// Render [score] as a 16-bit mono WAV using Karplus-Strong plucked-string
/// synthesis. [bpm] overrides the score's marked tempo (the beat grid scales
/// with it, so the metronome preset just uses the same value). Downbeats are
/// played slightly louder, mirroring the metronome's accent.
Uint8List renderScoreWav(Score score, {int? bpm}) {
  const rate = 22050;
  final effBpm = (bpm ?? score.bpm).clamp(20, 300);
  final secPerBeat = 60.0 / effBpm;
  const tailSec = 1.2; // let the last note ring out

  final n = ((score.totalBeats * secPerBeat + tailSec) * rate).ceil();
  final mix = Float64List(n);
  final rnd = math.Random(7); // deterministic pick noise → stable output

  var beatPos = 0.0;
  for (final note in score.notes) {
    final midi = note.midi;
    if (midi != null) {
      final start = (beatPos * secPerBeat * rate).round();
      final freq = 440 * math.pow(2, (midi - 69) / 12).toDouble();
      final period = (rate / freq).round().clamp(2, 2000);
      // Karplus-Strong: a noise burst (the pick) circulating through a delay
      // line with averaging (the string's damping) decays into a pluck tone.
      final string = Float64List(period);
      for (var i = 0; i < period; i++) {
        string[i] = rnd.nextDouble() * 2 - 1;
      }
      final onDownbeat = beatPos % score.beatsPerBar == 0;
      final amp = onDownbeat ? 0.62 : 0.5;
      final len = math.min(
        ((note.beats * secPerBeat + 0.9) * rate).round(), // ring past the beat
        n - start,
      );
      var idx = 0;
      for (var s = 0; s < len; s++) {
        final out = string[idx];
        string[idx] = 0.996 * 0.5 * (out + string[(idx + 1) % period]);
        idx = (idx + 1) % period;
        mix[start + s] += out * amp;
      }
    }
    beatPos += note.beats;
  }

  // Normalize to a comfortable peak.
  var peak = 1e-9;
  for (final v in mix) {
    final a = v.abs();
    if (a > peak) peak = a;
  }
  final gain = 0.8 / peak;

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
  for (var i = 0; i < n; i++) {
    data.setInt16(44 + i * 2, (mix[i] * gain * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}
