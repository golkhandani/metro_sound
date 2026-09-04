import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:metro_sound/services/score_synth.dart';

void main() {
  const rate = 22050;

  int sampleAt(Uint8List wav, int i) =>
      ByteData.sublistView(wav).getInt16(44 + i * 2, Endian.little);

  // RMS over a short window starting at sample [start].
  double energy(Uint8List wav, int start, [int win = 512]) {
    var sum = 0.0;
    for (var i = start; i < start + win; i++) {
      final s = sampleAt(wav, i) / 32768.0;
      sum += s * s;
    }
    return sum / win;
  }

  test('renders a valid 22.05kHz mono 16-bit WAV of the expected length', () {
    final wav = renderScoreWav(sampleScore);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    final bd = ByteData.sublistView(wav);
    expect(bd.getUint16(22, Endian.little), 1); // mono
    expect(bd.getUint32(24, Endian.little), rate);
    final expectedSamples =
        ((sampleScore.totalBeats * 60.0 / sampleScore.bpm + 1.2) * rate).ceil();
    expect(bd.getUint32(40, Endian.little), expectedSamples * 2);
    expect(wav.length, 44 + expectedSamples * 2);
  });

  test('notes land exactly on the beat grid', () {
    final wav = renderScoreWav(sampleScore);
    final samplesPerBeat = 60.0 / sampleScore.bpm * rate;
    // Every integer beat in the first phrase starts a note (quarters), so a
    // fresh pluck transient must sit right at each boundary: the onset window
    // is markedly louder than the decayed tail just before it.
    for (var beat = 1; beat <= 6; beat++) {
      final at = (beat * samplesPerBeat).round();
      expect(energy(wav, at), greaterThan(energy(wav, at - 600) * 1.5),
          reason: 'no pluck onset at beat $beat');
    }
  });

  test('bpm override scales the grid', () {
    final slow = renderScoreWav(sampleScore, bpm: 35);
    final fast = renderScoreWav(sampleScore, bpm: 140);
    expect(slow.length, greaterThan(fast.length * 2));
  });

  test('output is deterministic', () {
    expect(renderScoreWav(sampleScore), renderScoreWav(sampleScore));
  });
}
