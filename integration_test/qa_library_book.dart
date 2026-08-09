import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_common.dart';

/// QA sweep — Library (Books) + Book screen + track/book context menus + Pro
/// gating. Share actions that terminate in a native share sheet are captured at
/// the menu level only (firing them would open an uncapturable OS sheet).
void main() {
  ensureBinding();

  testWidgets('QA: Library + Book', (tester) async {
    await boot(tester);
    await goLibrary(tester);
    await shot(tester, 'lib-01-library-grid');

    // Book context menu (⋯ on first tile).
    await tapIcon(tester, Icons.more_horiz);
    await shot(tester, 'lib-02-book-context-menu');
    await tester.tapAt(const Offset(200, 24)); // dismiss barrier
    await settle(tester);

    // Rename book -> prompt.
    await tapIcon(tester, Icons.more_horiz);
    await tapText(tester, 'Rename');
    await shot(tester, 'lib-03-book-rename-prompt');
    await tapText(tester, 'Cancel');

    // New book while at free-tier cap (5 seeded books, not Pro) -> Pro sheet.
    await tapTip(tester, 'New book');
    await shot(tester, 'lib-04-newbook-pro-gate');
    await tapText(tester, 'Not now');

    // Import shared library while capped -> Pro sheet (no native picker).
    await tapTip(tester, 'Import shared library');
    await shot(tester, 'lib-05-import-pro-gate');
    await tapText(tester, 'Not now');

    // Open the first book (tap its unique subtitle).
    await tapText(tester, '7 tracks');
    await shot(tester, 'book-01-track-list');

    // Track context menu (⋯ on first row).
    await tapIcon(tester, Icons.more_horiz);
    await shot(tester, 'book-02-track-context-menu');
    await tester.tapAt(const Offset(200, 24));
    await settle(tester);

    // Mark a track done via the menu, then observe the row + progress bar.
    await tapIcon(tester, Icons.more_horiz);
    await tapText(tester, 'Mark as not done'); // first tracks are seeded done
    await shot(tester, 'book-03-track-marked-not-done');

    // Track rename prompt.
    await tapIcon(tester, Icons.more_horiz);
    await tapText(tester, 'Rename');
    await shot(tester, 'book-04-track-rename-prompt');
    await tapText(tester, 'Cancel');

    // Track delete -> confirm dialog (cancel to preserve content).
    await tapIcon(tester, Icons.more_horiz);
    await tapText(tester, 'Delete');
    await shot(tester, 'book-05-track-delete-confirm');
    await tapText(tester, 'Cancel');

    // Reorder: drag the first track's handle downward.
    final handle = find.byIcon(Icons.drag_handle);
    if (handle.evaluate().isNotEmpty) {
      await tester.drag(handle.first, const Offset(0, 140), warnIfMissed: false);
      await shot(tester, 'book-06-after-reorder');
    }

    // App-bar Record while not Pro -> Pro sheet (recorder gate).
    await tapTip(tester, 'Record a track');
    await shot(tester, 'book-07-record-pro-gate');
    await tapText(tester, 'Not now');

    await back(tester); // back to Library
    await shot(tester, 'lib-06-back-to-library');
  });
}
