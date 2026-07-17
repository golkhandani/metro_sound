import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings.dart';
import '../ui/studio.dart';
import 'package_job_overlay.dart' show appNavigatorKey;

/// One spotlighted step of a screen's tutorial.
class CoachTarget {
  final GlobalKey key;
  final String title;
  final String body;
  const CoachTarget(this.key, this.title, this.body);
}

/// All coach-mark anchor keys live here so screens (which attach them) and
/// RootShell (which triggers) share them without import cycles. Static keys
/// are safe: every anchored widget is a singleton (tabs live once in the
/// IndexedStack; one BookScreen/PlayerScreen route at a time).
class CoachKeys {
  static final booksNewBook = GlobalKey();
  static final booksImport = GlobalKey();
  static final booksFirstTile = GlobalKey();

  static final metroBpm = GlobalKey();
  static final metroTap = GlobalKey();
  static final metroTimeSig = GlobalKey();

  static final tunerGauge = GlobalKey();
  static final tunerNotation = GlobalKey();

  static final settingsMetroCard = GlobalKey();
  static final settingsShareCard = GlobalKey();

  static final bookImport = GlobalKey();
  static final bookRecord = GlobalKey();
  static final bookShare = GlobalKey();

  static final playerSpeed = GlobalKey();
  static final playerLock = GlobalKey();
  static final playerWave = GlobalKey();
}

/// The per-screen tutorial scripts (copy + anchors).
class CoachScripts {
  static List<CoachTarget> of(String screenId) => switch (screenId) {
    'library' => [
      CoachTarget(
        CoachKeys.booksNewBook,
        'New book',
        'Create a book — one folder per method book or course.',
      ),
      CoachTarget(
        CoachKeys.booksImport,
        'Import',
        'Add a library or book someone shared with you.',
      ),
      CoachTarget(
        CoachKeys.booksFirstTile,
        'Your books',
        'Tap to open. Long-press for cover, rename, share and more.',
      ),
    ],
    'metronome' => [
      CoachTarget(
        CoachKeys.metroBpm,
        'Tempo fader',
        'Drag to set the BPM, or use the ± steppers.',
      ),
      CoachTarget(
        CoachKeys.metroTap,
        'Tap tempo',
        'Tap along with a song to find its tempo.',
      ),
      CoachTarget(
        CoachKeys.metroTimeSig,
        'Time signature',
        'Pick anything from 2/4 to 12/8.',
      ),
    ],
    'tuner' => [
      CoachTarget(
        CoachKeys.tunerGauge,
        'Pitch gauge',
        'Play a note — the center of the dial is expanded so the '
            'last few cents are easy to see.',
      ),
      CoachTarget(
        CoachKeys.tunerNotation,
        'Note names',
        'Switch letters/solfège, ♭/♯, and Persian quarter-tones.',
      ),
    ],
    'settings' => [
      CoachTarget(
        CoachKeys.settingsMetroCard,
        'Metronome defaults',
        'Lock the click to your music so it never drifts.',
      ),
      CoachTarget(
        CoachKeys.settingsShareCard,
        'Share libraries',
        'Send your whole library as one file, or import one you '
            'received.',
      ),
    ],
    'book' => [
      CoachTarget(
        CoachKeys.bookImport,
        'Import audio',
        'Add mp3/m4a files from your device into this book.',
      ),
      CoachTarget(
        CoachKeys.bookRecord,
        'Record',
        'Record a practice take straight into the book.',
      ),
      CoachTarget(
        CoachKeys.bookShare,
        'Share book',
        'Send this book — audio, photos and settings — as one file.',
      ),
    ],
    'player' => [
      CoachTarget(
        CoachKeys.playerWave,
        'Waveform',
        'Tap or drag anywhere to scrub the track.',
      ),
      CoachTarget(
        CoachKeys.playerSpeed,
        'Speed',
        'Slow a track down to practice — the metronome follows.',
      ),
      CoachTarget(
        CoachKeys.playerLock,
        'Lock to music',
        'The click follows the track position so it never drifts.',
      ),
    ],
    _ => const [],
  };
}

/// Spotlight tutorial engine: one overlay at a time, per-screen scripts,
/// each shown once (persisted via AppSettings.seenTips).
class CoachMarks {
  static bool _active = false;

  static void maybeShow(BuildContext context, String screenId) {
    final settings = context.read<AppSettings>();
    if (!settings.onboardingDone) {
      debugPrint('coach[$screenId]: skipped — onboarding not done');
      return; // never during/before onboarding
    }
    if (settings.tipSeen(screenId)) return;
    if (_active) {
      debugPrint('coach[$screenId]: skipped — another coach active');
      return;
    }

    // Keep only targets that are actually laid out right now.
    final all = CoachScripts.of(screenId);
    final targets = all.where((t) {
      final box = t.key.currentContext?.findRenderObject();
      return box is RenderBox && box.attached && box.hasSize;
    }).toList();
    debugPrint(
      'coach[$screenId]: ${targets.length}/${all.length} anchors mounted',
    );
    // No anchors (e.g. empty grid): don't mark seen — re-arm for next visit.
    if (targets.isEmpty) return;

    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) {
      debugPrint('coach[$screenId]: skipped — no overlay');
      return;
    }

    _active = true;
    late OverlayEntry entry;
    void finish() {
      settings.markTipSeen(screenId);
      entry.remove();
      _active = false;
    }

    entry = OverlayEntry(
      builder: (_) => _CoachOverlay(targets: targets, onFinish: finish),
    );
    overlay.insert(entry);
  }
}

/// Wrap a pushed route's scaffold to run its coach marks once the push
/// animation settles (so anchor rects are measured in place).
class CoachTrigger extends StatefulWidget {
  final String screenId;
  final Widget child;
  const CoachTrigger({super.key, required this.screenId, required this.child});

  @override
  State<CoachTrigger> createState() => _CoachTriggerState();
}

class _CoachTriggerState extends State<CoachTrigger> {
  bool _fired = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fired) return;
    _fired = true;
    final route = ModalRoute.of(context);
    final anim = route?.animation;
    if (anim == null || anim.isCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) CoachMarks.maybeShow(context, widget.screenId);
      });
      return;
    }
    late void Function(AnimationStatus) listener;
    listener = (status) {
      if (status == AnimationStatus.completed) {
        anim.removeStatusListener(listener);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) CoachMarks.maybeShow(context, widget.screenId);
        });
      }
    };
    anim.addStatusListener(listener);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ───────────────────────── Overlay ─────────────────────────

class _CoachOverlay extends StatefulWidget {
  final List<CoachTarget> targets;
  final VoidCallback onFinish;
  const _CoachOverlay({required this.targets, required this.onFinish});

  @override
  State<_CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends State<_CoachOverlay>
    with WidgetsBindingObserver {
  int _step = 0;
  Rect? _rect;
  Rect? _prevRect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _goTo(0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // Rotation / resize: re-measure the current anchor next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _goTo(int step) async {
    if (step >= widget.targets.length) {
      widget.onFinish();
      return;
    }
    _step = step;
    final ctx = widget.targets[step].key.currentContext;
    if (ctx == null) {
      _goTo(step + 1); // anchor vanished — skip it
      return;
    }
    // Bring scrollable anchors into view before measuring.
    try {
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    // addPostFrameCallback doesn't itself schedule a frame — if the app is
    // idle (e.g. right after the onboarding fade), the callback would never
    // run and the coach would stall on a plain dim. Force the frame.
    WidgetsBinding.instance.scheduleFrame();
  }

  void _measure() {
    if (!mounted) return;
    final box = widget.targets[_step].key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      debugPrint('coach: step $_step anchor unmeasurable — advancing');
      _goTo(_step + 1);
      return;
    }
    setState(() {
      _prevRect = _rect;
      _rect = box.localToGlobal(Offset.zero) & box.size;
      debugPrint('coach: step $_step rect=$_rect');
    });
  }

  void _next() => _goTo(_step + 1);

  @override
  Widget build(BuildContext context) {
    final rect = _rect;
    final media = MediaQuery.of(context);
    final screen = media.size;
    final target = widget.targets[_step];
    final last = _step == widget.targets.length - 1;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Dim + cutout. Opaque barrier: absorbs everything (no tabbing away
          // mid-coach); tap anywhere advances.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _next,
              child: rect == null
                  ? ColoredBox(color: Studio.dim)
                  : TweenAnimationBuilder<Rect?>(
                      tween: RectTween(begin: _prevRect ?? rect, end: rect),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      builder: (_, r, _) => CustomPaint(
                        size: screen,
                        painter: _DimPainter(r ?? rect),
                      ),
                    ),
            ),
          ),
          if (rect != null) _caption(target, rect, screen, media, last),
        ],
      ),
    );
  }

  Widget _caption(
    CoachTarget target,
    Rect rect,
    Size screen,
    MediaQueryData media,
    bool last,
  ) {
    final below = rect.center.dy < screen.height / 2;
    final w = math.min(screen.width - 40, 340.0);
    final left = (rect.center.dx - w / 2)
        .clamp(20.0, math.max(20.0, screen.width - 20 - w))
        .toDouble();

    final card = TweenAnimationBuilder<double>(
      key: ValueKey(_step),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * (below ? 10 : -10)),
          child: child,
        ),
      ),
      child: Container(
        width: w,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        decoration: BoxDecoration(
          color: Studio.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Studio.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_step + 1} OF ${widget.targets.length}',
              style: Studio.label.copyWith(color: Studio.amber),
            ),
            const SizedBox(height: 6),
            Text(target.title, style: Studio.title),
            const SizedBox(height: 4),
            Text(target.body, style: Studio.bodyDim),
            const SizedBox(height: 10),
            Row(
              children: [
                StudioButton(
                  label: 'Skip',
                  kind: StudioButtonKind.ghost,
                  onTap: widget.onFinish,
                ),
                const Spacer(),
                StudioButton(label: last ? 'Done' : 'Next', onTap: _next),
              ],
            ),
          ],
        ),
      ),
    );

    return below
        ? Positioned(
            left: left,
            top: math.max(media.padding.top + 12.0, rect.bottom + 16.0),
            child: card,
          )
        : Positioned(
            left: left,
            bottom: math.max(
              media.padding.bottom + 12.0,
              screen.height - rect.top + 16.0,
            ),
            child: card,
          );
  }
}

class _DimPainter extends CustomPainter {
  final Rect rect;
  const _DimPainter(this.rect);

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(
      rect.inflate(6),
      const Radius.circular(12),
    );
    final dim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(hole),
    );
    canvas.drawPath(dim, Paint()..color = Studio.dim);
    // Amber ring + soft glow around the spotlight.
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Studio.amber.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Studio.amber,
    );
  }

  @override
  bool shouldRepaint(covariant _DimPainter old) => old.rect != rect;
}
