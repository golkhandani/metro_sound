import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_common.dart';

/// QA sweep — Settings (Pro card, theme, toggles, shares, import gate),
/// Advanced (test tools, all confirmed-cancelled), the package progress sheet
/// (via a cancellable library export), and Replay tutorial → onboarding →
/// coach marks. Runs WITHOUT QAPRO so the paywall/gates are reachable.
void main() {
  ensureBinding();

  testWidgets('QA: Settings + Advanced + onboarding', (tester) async {
    await boot(tester);
    await goSettings(tester);
    await shot(tester, 'settings-01-initial');

    // Pro sheet from the Pro card.
    final unlock = find.textContaining('Unlock Pro');
    if (unlock.evaluate().isNotEmpty) {
      await tester.tap(unlock.first, warnIfMissed: false);
      await shot(tester, 'settings-02-pro-sheet');
      await tapText(tester, 'Not now');
    }

    // Metronome section toggles.
    await toggleSwitch(tester, 0);
    await toggleSwitch(tester, 1);
    await shot(tester, 'settings-03-toggles');
    await toggleSwitch(tester, 0);
    await toggleSwitch(tester, 1);

    // Appearance: Light across a couple of screens, then Dark, then System.
    await tapText(tester, 'Light');
    await shot(tester, 'settings-04-light');
    await goLibrary(tester);
    await shot(tester, 'theme-light-library');
    await goMetronome(tester);
    await shot(tester, 'theme-light-metronome');
    await goSettings(tester);
    await tapText(tester, 'Dark');
    await shot(tester, 'settings-05-dark');
    await goLibrary(tester);
    await shot(tester, 'theme-dark-library');
    await goMetronome(tester);
    await shot(tester, 'theme-dark-metronome');
    await goSettings(tester);
    await tapText(tester, 'System');

    // Advanced (test tools) — every action confirmed then cancelled.
    await tapText(tester, 'Storage & data cleanup');
    await shot(tester, 'advanced-01-initial');
    await tapText(tester, 'Clear cache');
    await shot(tester, 'advanced-02-clearcache-confirm');
    await tapText(tester, 'Cancel');
    await tapText(tester, 'Erase all data');
    await shot(tester, 'advanced-03-erase-confirm');
    await tapText(tester, 'Cancel');
    await tapText(tester, 'Reset purchase (local)');
    await shot(tester, 'advanced-04-reset-confirm');
    await tapText(tester, 'Cancel');
    await back(tester); // -> Settings

    // Scroll down to reveal the Share libraries + Help sections (lazy list).
    await tester.drag(
        find.byType(Scrollable).first, const Offset(0, -1100),
        warnIfMissed: false);
    await settle(tester);
    await shot(tester, 'settings-06-shares-section');

    // Import shared library while capped/not-Pro -> Pro sheet.
    await tapText(tester, 'Import shared library');
    await shot(tester, 'settings-07-import-gate');
    await tapText(tester, 'Not now');

    // Share my library -> package export + progress sheet; cancel before the
    // native share sheet appears.
    await tapText(tester, 'Share my library', ms: 250);
    await shot(tester, 'settings-08-share-progress');
    await tapText(tester, 'Cancel');
    await settle(tester);

    // Scroll further for the Help section.
    await tester.drag(
        find.byType(Scrollable).first, const Offset(0, -600),
        warnIfMissed: false);
    await settle(tester);

    // Replay tutorial -> onboarding.
    await tapText(tester, 'Replay tutorial');
    await shot(tester, 'onboarding-01');
    final pv = find.byType(PageView);
    for (var i = 2; i <= 4; i++) {
      if (pv.evaluate().isEmpty) break;
      await tester.drag(pv.first, const Offset(-400, 0), warnIfMissed: false);
      await shot(tester, 'onboarding-0$i');
    }
    await tapText(tester, 'Get started');
    // Coach marks may appear over Library.
    await shot(tester, 'coachmarks-01');
    // Dismiss any coach-mark run.
    await tapText(tester, 'Skip');
    await tapText(tester, 'Skip');
    await settle(tester);
    await shot(tester, 'settings-08-final');
  });
}
