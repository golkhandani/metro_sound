import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_common.dart';

/// QA sweep — Player screen (speed, metronome, mixer, transport, sync) and the
/// Photo Viewer. The native "Add photo" picker is not fired (uncapturable).
void main() {
  ensureBinding();

  testWidgets('QA: Player + Photo viewer', (tester) async {
    await boot(tester);
    await goLibrary(tester);
    await tapText(tester, '7 tracks'); // open first book
    await tapTip(tester, 'Play all'); // open Player at track 0
    await shot(tester, 'player-01-initial');

    // Speed presets.
    await tapText(tester, '2×');
    await shot(tester, 'player-02-speed-2x');
    await tapText(tester, '1×');

    // Time-signature menu (current label is one of these).
    for (final sig in const ['4/4', '3/4', '6/8', '2/4', '5/4']) {
      if (await tapText(tester, sig)) break;
    }
    await shot(tester, 'player-03-timesig-menu');
    await tapText(tester, '7 / 8'); // menu uses spaced labels
    if (find.text('TIME SIGNATURE').evaluate().isNotEmpty) {
      await tester.tapAt(const Offset(200, 24)); // dismiss if still open
      await settle(tester);
    }
    await shot(tester, 'player-04-timesig-picked');

    // BPM steppers (BPM +/- are the first remove/add on the page).
    await tapIcon(tester, Icons.add);
    await tapIcon(tester, Icons.add);
    await shot(tester, 'player-05-bpm-up');
    await tapIcon(tester, Icons.remove);
    await shot(tester, 'player-06-bpm-down');

    // Start the click (metronome running → pendulum animates).
    await tapText(tester, 'Click');
    await shot(tester, 'player-07-metronome-running');
    await tapText(tester, 'Stop');

    // Toggle the metronome-related switches (Visual / Lock / Done).
    await toggleSwitch(tester, 0);
    await shot(tester, 'player-08-switch0-toggled');
    await toggleSwitch(tester, 1);
    await shot(tester, 'player-09-switch1-toggled');

    // Transport: play (last play_arrow is the transport button), then pause.
    final play = find.byIcon(Icons.play_arrow);
    if (play.evaluate().isNotEmpty) {
      await tester.tap(play.last, warnIfMissed: false);
      await shot(tester, 'player-10-playing');
      final pause = find.byIcon(Icons.pause);
      if (pause.evaluate().isNotEmpty) {
        await tester.tap(pause.last, warnIfMissed: false);
        await settle(tester);
      }
    }
    // Scroll down to reveal Mixer / Photos / Done cards (still on track 0,
    // which has the seeded photos — do this BEFORE skipping tracks).
    final sc = find.byType(Scrollable);
    if (sc.evaluate().isNotEmpty) {
      await tester.drag(sc.first, const Offset(0, -600), warnIfMissed: false);
      await shot(tester, 'player-11-scrolled-lower');
      await tester.drag(sc.first, const Offset(0, -600), warnIfMissed: false);
      await shot(tester, 'player-12-scrolled-bottom');
    }

    // Photos: open the viewer via the "View" button (track 0 has photos).
    if (await tapText(tester, 'View')) {
      await shot(tester, 'photo-01-viewer');
      final pv = find.byType(PageView);
      if (pv.evaluate().isNotEmpty) {
        await tester.drag(pv.first, const Offset(-400, 0), warnIfMissed: false);
        await shot(tester, 'photo-02-swiped');
      }
      // Delete-photo confirm (cancel to preserve).
      if (await tapTip(tester, 'Delete photo')) {
        await shot(tester, 'photo-03-delete-confirm');
        await tapText(tester, 'Cancel');
      }
      await back(tester); // back to Player
    }

    // Skip to next track (after photos so we don't leave the photo track).
    await tapIcon(tester, Icons.skip_next);
    await shot(tester, 'player-13-next-track');

    await back(tester); // Player -> Book
    await back(tester); // Book -> Library
    await shot(tester, 'player-14-back-to-library');
  });
}
