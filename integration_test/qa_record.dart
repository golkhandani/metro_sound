import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_common.dart';

/// QA sweep — Record screen. Runs with --dart-define=QAPRO=1 so the Pro-gated
/// Record button opens the screen. Mic is pre-granted on the sim; the simulator
/// has no real input so the recorder may show its error state — captured either
/// way. Native share/picker never fired.
void main() {
  ensureBinding();

  testWidgets('QA: Record', (tester) async {
    await boot(tester);
    await goLibrary(tester);
    await dismissCoachMarks(tester);
    // Open whatever book exists (QASEED seed or the Getting Started sample).
    for (final t in const ['7 tracks', '5 tracks', 'Getting Started', '9 tracks']) {
      if (await tapText(tester, t)) break;
    }
    await tapTip(tester, 'Record a track', ms: 1500); // Pro-unlocked via QAPRO
    await settle(tester, 1500);
    await shot(tester, 'record-01-initial');
    await settle(tester, 1000);
    await shot(tester, 'record-01b-settled');

    // Recording settings sheet.
    if (await tapTip(tester, 'Recording settings')) {
      await shot(tester, 'record-02-settings');
      await toggleSwitch(tester, 0); // count-in
      await toggleSwitch(tester, 1); // click while recording
      await tapText(tester, 'Voice 22k');
      await shot(tester, 'record-03-settings-changed');
      await tapText(tester, 'High 44k');
      await tester.tapAt(const Offset(200, 24)); // dismiss sheet
      await settle(tester);
    }

    // Start capture (may count-in first).
    if (await tapIcon(tester, Icons.fiber_manual_record)) {
      await shot(tester, 'record-04-recording');
      await settle(tester, 1200);
      await shot(tester, 'record-05-recording-progress');
      // Pause / resume.
      if (await tapIcon(tester, Icons.pause)) {
        await shot(tester, 'record-06-paused');
        await tapIcon(tester, Icons.fiber_manual_record); // resume
        await settle(tester, 800);
      }
      // Stop -> review.
      if (await tapIcon(tester, Icons.stop)) {
        await shot(tester, 'record-07-review');
        // Preview the trimmed selection.
        await tapText(tester, 'Preview');
        await shot(tester, 'record-08-preview');
        // Save -> name prompt (cancel to keep the library clean).
        await tapText(tester, 'Save');
        await shot(tester, 'record-09-save-prompt');
        await tapText(tester, 'Cancel');
      }
    }

    await back(tester, times: 3);
  });
}
