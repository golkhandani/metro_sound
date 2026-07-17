import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings.dart';
import '../ui/studio.dart';

/// First-launch feature tour: four swipeable pages, skippable, shown once
/// (gated by AppSettings.onboardingDone in main.dart). Replayable from
/// Settings → Replay tutorial.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pc = PageController();
  int _page = 0;

  static const _pageCount = 4;
  bool get _last => _page == _pageCount - 1;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _next() {
    if (_last) {
      _finish();
    } else {
      _pc.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _finish() => context.read<AppSettings>().setOnboardingDone(true);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Studio.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Skip (hidden on the last page — "Get started" takes over).
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AnimatedOpacity(
                    opacity: _last ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: Pressable(
                      onTap: _last ? () {} : _finish,
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('SKIP', style: Studio.label),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pc,
                onPageChanged: (i) => setState(() => _page = i),
                children: const [
                  _Page(
                    illustration: _WelcomeArt(),
                    title: 'Welcome to Metro Sound',
                    body:
                        'Your practice studio — player, metronome '
                        'and tuner in one place.',
                  ),
                  _Page(
                    illustration: _BooksArt(),
                    title: 'Organize your practice',
                    body:
                        'Create books for your courses — import audio '
                        'files or record straight into them.',
                  ),
                  _Page(
                    illustration: _ToolsArt(),
                    title: 'Tools that stay in sync',
                    body:
                        'The metronome locks to your music so the click '
                        'never drifts — plus a precise tuner.',
                  ),
                  _Page(
                    illustration: _ShareArt(),
                    title: 'Share your library',
                    body:
                        'Send a book or your whole library as one file — '
                        'AirDrop, Messages, anything.',
                  ),
                ],
              ),
            ),
            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pageCount; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? Studio.amber : Studio.line,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: StudioButton(
                  label: _last ? 'Get started' : 'Next',
                  icon: _last ? Icons.check : Icons.arrow_forward,
                  onTap: _next,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  final Widget illustration;
  final String title;
  final String body;
  const _Page({
    required this.illustration,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(flex: 4, child: Center(child: illustration)),
        Text(
          title,
          style: Studio.title.copyWith(fontSize: 22),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Text(
            body,
            style: Studio.bodyDim.copyWith(fontSize: 14, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ),
        const Spacer(),
      ],
    );
  }
}

// ───────────────────────── Code-drawn illustrations ─────────────────────────

/// Page 1 — glowing app mark.
class _WelcomeArt extends StatelessWidget {
  const _WelcomeArt();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            color: Studio.surfaceHigh,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Studio.line),
            boxShadow: [
              BoxShadow(
                color: Studio.amber.withValues(alpha: 0.35),
                blurRadius: 40,
              ),
            ],
          ),
          child: Icon(Icons.av_timer, size: 52, color: Studio.amber),
        ),
        const SizedBox(height: 20),
        Text(
          'METRO SOUND',
          style: Studio.label.copyWith(fontSize: 13, letterSpacing: 4),
        ),
      ],
    );
  }
}

/// Page 2 — a mini library grid.
class _BooksArt extends StatelessWidget {
  const _BooksArt();

  Widget _tile(String seed, {String? badge}) {
    final h = seed.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff);
    final hue = (h % 360).toDouble();
    return Container(
      width: 58,
      height: 86,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Studio.line),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue, 0.45, 0.40).toColor(),
            HSLColor.fromAHSL(1, (hue + 28) % 360, 0.50, 0.22).toColor(),
          ],
        ),
      ),
      child: badge == null
          ? Icon(
              Icons.album_outlined,
              size: 22,
              color: Colors.white.withValues(alpha: 0.55),
            )
          : Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                margin: const EdgeInsets.all(5),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Studio.bg.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Studio.line),
                ),
                child: Text(
                  badge,
                  style: Studio.numeric(9, color: Studio.amber),
                ),
              ),
            ),
    );
  }

  Widget _glyph(IconData icon) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: Studio.surfaceHigh,
      shape: BoxShape.circle,
      border: Border.all(color: Studio.line),
    ),
    child: Icon(icon, size: 17, color: Studio.amber),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tile('Tar'),
            const SizedBox(width: 12),
            _tile('Setar', badge: '3/8'),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tile('Violin'),
            const SizedBox(width: 12),
            _tile('Piano'),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _glyph(Icons.add),
            const SizedBox(width: 12),
            _glyph(Icons.mic_none),
          ],
        ),
      ],
    );
  }
}

/// Page 3 — mini tuner gauge + lock badge.
class _ToolsArt extends StatelessWidget {
  const _ToolsArt();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 260,
          height: 130,
          child: CustomPaint(painter: _MiniGauge()),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Studio.amberSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Studio.amber),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_clock, size: 14, color: Studio.amber),
              const SizedBox(width: 6),
              Text(
                'LOCKED TO MUSIC',
                style: Studio.label.copyWith(fontSize: 9, color: Studio.amber),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniGauge extends CustomPainter {
  const _MiniGauge();
  static const double _maxA = 50 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width / 2, size.height - 4);
    final r = size.height * 0.9;
    final rect = Rect.fromCircle(center: pivot, radius: r);
    canvas.drawArc(
      rect,
      -math.pi / 2 - _maxA,
      2 * _maxA,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Studio.line,
    );
    // In-tune zone
    canvas.drawArc(
      rect,
      -math.pi / 2 - 0.18,
      0.36,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = Studio.teal.withValues(alpha: 0.6),
    );
    // Needle at a slight offset
    const na = 12 * math.pi / 180;
    final dir = Offset(math.sin(na), -math.cos(na));
    canvas.drawLine(
      pivot,
      pivot + dir * (r - 6),
      Paint()
        ..color = Studio.amber
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(pivot, 6, Paint()..color = Studio.amber);
  }

  @override
  bool shouldRepaint(covariant _MiniGauge oldDelegate) => false;
}

/// Page 4 — share → import exchange.
class _ShareArt extends StatelessWidget {
  const _ShareArt();

  Widget _card(IconData icon, String label, Color accent) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Studio.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Studio.line),
        ),
        child: Icon(icon, size: 30, color: accent),
      ),
      const SizedBox(height: 8),
      Text(label, style: Studio.label.copyWith(fontSize: 9)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _card(Icons.ios_share, 'SHARE', Studio.amber),
        const SizedBox(width: 14),
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Studio.amber,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        _card(Icons.download_outlined, 'IMPORT', Studio.teal),
      ],
    );
  }
}
