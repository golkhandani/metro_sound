import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_common.dart';

/// QA sweep — Metronome tab and Tuner tab (mic priming dialog + notation
/// controls). Mic permission is pre-granted on the sim so no native prompt
/// blocks the run; the simulator has no real audio input, so the tuner shows
/// its idle/listening state.
void main() {
  ensureBinding();

  testWidgets('QA: Metronome + Tuner', (tester) async {
    await boot(tester);

    // ── Metronome tab ──
    await goMetronome(tester);
    await shot(tester, 'metro-01-initial');

    // VISUAL switch off/on.
    await toggleSwitch(tester, 0);
    await shot(tester, 'metro-02-visual-off');
    await toggleSwitch(tester, 0);

    // BPM steppers.
    await tapIcon(tester, Icons.add);
    await tapIcon(tester, Icons.add);
    await shot(tester, 'metro-03-bpm-up');
    await tapIcon(tester, Icons.remove);

    // Tap-tempo (a few taps).
    await tapText(tester, 'Tap');
    await tapText(tester, 'Tap');
    await shot(tester, 'metro-04-after-tap');

    // Time-signature menu.
    for (final sig in const ['4/4', '3/4', '6/8', '2/4']) {
      if (await tapText(tester, sig)) break;
    }
    await shot(tester, 'metro-05-timesig-menu');
    await tapText(tester, '5 / 4'); // menu uses spaced labels
    if (find.text('TIME SIGNATURE').evaluate().isNotEmpty) {
      await tester.tapAt(const Offset(200, 24)); // dismiss if still open
      await settle(tester);
    }
    await shot(tester, 'metro-06-timesig-picked');

    // Start (pendulum animates), then stop.
    await tapIcon(tester, Icons.play_arrow);
    await shot(tester, 'metro-07-running');
    // Volume mute toggle while running.
    await tapIcon(tester, Icons.volume_up);
    await shot(tester, 'metro-08-muted');
    await tapIcon(tester, Icons.volume_off);
    await tapIcon(tester, Icons.stop);

    // ── Tuner tab ── (first entry → mic priming dialog)
    await goTuner(tester);
    await shot(tester, 'tuner-01-priming-dialog');
    await tapText(tester, 'Continue');
    await shot(tester, 'tuner-02-listening');

    // Note naming.
    await tapText(tester, 'Do Re Mi');
    await shot(tester, 'tuner-03-solfege');
    await tapText(tester, 'C D E');

    // Accidental.
    await tapText(tester, '♯');
    await shot(tester, 'tuner-04-sharps');
    await tapText(tester, '♭ ♯');
    await shot(tester, 'tuner-05-both');

    // Quarter-tones switch.
    await toggleSwitch(tester, 0);
    await shot(tester, 'tuner-06-quartertones');

    await goLibrary(tester); // stop mic, leave clean
  });
}
