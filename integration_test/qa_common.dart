import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:metro_sound/main.dart' as app;
import 'package:metro_sound/ui/studio.dart';

/// Shared helpers for the automated QA sweep. Each area test file boots the real
/// app (seeded via --dart-define=QASEED=1), drives a page's controls, and calls
/// [shot] after each state change to capture a screenshot.
late IntegrationTestWidgetsFlutterBinding binding;

IntegrationTestWidgetsFlutterBinding ensureBinding() {
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  return binding;
}

Future<void> boot(WidgetTester tester) async {
  await app.main();
  await settle(tester, 1200);
  // Skip onboarding if it appears, so each run is independent of persisted
  // state left by a prior run's "Replay tutorial".
  final skip = find.text('SKIP');
  if (skip.evaluate().isNotEmpty) {
    await tester.tap(skip.first, warnIfMissed: false);
    await settle(tester, 800);
  }
  // Dismiss any auto-triggered coach marks so they don't block interaction.
  // Coach marks can appear a beat after the route settles, so retry a few times.
  for (var i = 0; i < 4; i++) {
    await settle(tester, 400);
    final skipCoach = find.text('Skip');
    if (skipCoach.evaluate().isEmpty) break;
    await tester.tap(skipCoach.first, warnIfMissed: false);
  }
}

/// Dismiss coach marks that appear after a navigation (retry a few frames).
Future<void> dismissCoachMarks(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await settle(tester, 400);
    final f = find.text('Skip');
    if (f.evaluate().isEmpty) break;
    await tester.tap(f.first, warnIfMissed: false);
  }
}

/// Settle that tolerates continuous animations (metronome pendulum, tuner gauge,
/// playing equalizer) which would make a plain pumpAndSettle time out.
Future<void> settle(WidgetTester tester, [int ms = 500]) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 80),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 4),
    );
  } catch (_) {
    // Animation never settles — that's fine, just render a few frames.
  }
  await tester.pump(Duration(milliseconds: ms));
}

Future<void> shot(WidgetTester tester, String name) async {
  await settle(tester);
  await binding.takeScreenshot(name);
}

// ── Finders / actions ──────────────────────────────────────────────────────

Finder byTip(String tip) => find.byTooltip(tip);

/// Tap the first match of a visible text (StudioButton, segmented option,
/// menu action, list title, etc.).
Future<bool> tapText(WidgetTester tester, String text, {int ms = 400}) async {
  final f = find.text(text);
  if (f.evaluate().isEmpty) return false;
  await tester.tap(f.first, warnIfMissed: false);
  await settle(tester, ms);
  return true;
}

Future<bool> tapTip(WidgetTester tester, String tip, {int ms = 400}) async {
  final f = find.byTooltip(tip);
  if (f.evaluate().isEmpty) return false;
  await tester.tap(f.first, warnIfMissed: false);
  await settle(tester, ms);
  return true;
}

Future<bool> tapIcon(WidgetTester tester, IconData icon, {int ms = 400}) async {
  final f = find.byIcon(icon);
  if (f.evaluate().isEmpty) return false;
  await tester.tap(f.first, warnIfMissed: false);
  await settle(tester, ms);
  return true;
}

/// Toggle the Nth StudioSwitch on screen.
Future<bool> toggleSwitch(WidgetTester tester, int index, {int ms = 400}) async {
  final f = find.byType(StudioSwitch);
  if (f.evaluate().length <= index) return false;
  await tester.tap(f.at(index), warnIfMissed: false);
  await settle(tester, ms);
  return true;
}

/// Drag the Nth Slider to a fraction (0..1) of its width.
Future<bool> dragSlider(WidgetTester tester, int index, double frac,
    {int ms = 400}) async {
  final f = find.byType(Slider);
  if (f.evaluate().length <= index) return false;
  final rect = tester.getRect(f.at(index));
  final y = rect.center.dy;
  final target = Offset(rect.left + rect.width * frac.clamp(0.02, 0.98), y);
  await tester.tapAt(target);
  await settle(tester, ms);
  return true;
}

// ── Bottom-nav navigation (by distinctive tab icons) ───────────────────────
Future<void> goLibrary(WidgetTester t) async => tapIcon(t, Icons.library_music);
Future<void> goMetronome(WidgetTester t) async => tapIcon(t, Icons.av_timer);
Future<void> goTuner(WidgetTester t) async => tapIcon(t, Icons.graphic_eq);
Future<void> goSettings(WidgetTester t) async => tapIcon(t, Icons.settings);

/// Pop the current pushed route. StudioScaffold uses a custom chevron_left back
/// button (not Flutter's BackButton / no 'Back' tooltip), so target that first.
Future<void> back(WidgetTester tester, {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    if (await tapIcon(tester, Icons.chevron_left)) continue;
    final f = find.byTooltip('Back');
    if (f.evaluate().isNotEmpty) {
      await tester.tap(f.first, warnIfMissed: false);
    } else {
      final nav = find.byType(BackButton);
      if (nav.evaluate().isNotEmpty) {
        await tester.tap(nav.first, warnIfMissed: false);
      }
    }
    await settle(tester);
  }
}
