import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_common.dart';

/// Verifies the "Getting Started" sample book seeds on a fresh/empty library
/// (run WITHOUT --dart-define=QASEED so the production seed path runs).
void main() {
  ensureBinding();

  testWidgets('QA: sample book seeds when library is empty', (tester) async {
    await boot(tester); // skips onboarding if shown
    await goLibrary(tester);
    await dismissCoachMarks(tester);
    await shot(tester, 'sample-01-fresh-library');
  });
}
