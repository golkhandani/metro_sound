import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/metronome.dart';
import '../services/tuner.dart';
import '../ui/studio.dart';
import '../dev/screenshot_director.dart';
import '../widgets/coach_marks.dart';
import 'books_screen.dart';
import 'metronome_screen.dart';
import 'settings_screen.dart';
import 'tuner_screen.dart';

/// Bottom-tab shell: Library · Metronome · Tuner · Settings. Detail screens
/// (book, player) push over the whole shell from the Library tab.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  // Survives the full-tree re-key that a theme switch performs, so changing
  // the theme from Settings lands you back on Settings, not the Library.
  static int _lastIndex = 0;
  int _index = ScreenshotDirector.initialTab ?? _lastIndex;
  static const _metroTab = 1;
  static const _tunerTab = 2;

  // Coach-mark ids per tab. The IndexedStack pre-builds every tab, so coach
  // marks are driven from HERE (actual visibility), never from screen builds.
  static const _screenIds = ['library', 'metronome', 'tuner', 'settings'];

  // Chains mic/session operations so they never overlap (see _select).
  Future<void> _audioOps = Future.value();
  void _queueAudioOp(Future<void> Function() op) {
    _audioOps = _audioOps.then((_) => op()).catchError((e) {
      debugPrint('audio op failed: \$e');
    });
  }

  @override
  void initState() {
    super.initState();
    ScreenshotDirector.direct(context);
    // First run: let the onboarding→shell fade settle, then coach the library.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted && _index == 0) {
          CoachMarks.maybeShow(context, _screenIds[0]);
        }
      });
    });
  }

  void _select(int i) {
    if (i == _index) {
      return;
    }
    final tuner = context.read<Tuner>();
    final metronome = context.read<Metronome>();
    final leavingMetronome = _index == _metroTab;
    final leavingTuner = _index == _tunerTab;
    setState(() => _index = i);
    _lastIndex = i;
    // Leaving the metronome tab stops the click (the IndexedStack keeps the
    // screen alive, so its dispose() never runs on tab switches).
    if (leavingMetronome) metronome.stop();
    // Mic + audio-session transitions must be strictly serialized: stop,
    // session restore, and (re)start race each other otherwise and the
    // capture engine dies with "listen failed" on quick tab hops.
    if (i == _tunerTab) {
      _queueAudioOp(() => tuner.start());
    } else if (leavingTuner) {
      _queueAudioOp(() async {
        await tuner.stop();
        // Let the capture engine finish tearing down before the session flips.
        await Future.delayed(const Duration(milliseconds: 150));
        // The mic put the shared iOS session in a record category, which
        // lowers playback volume; re-assert the playback session on the way
        // out so music and clicks come back at full volume.
        await metronome.restorePlaybackSession();
      });
    }
    // Coach the newly visible tab (re-check the index post-frame so rapid
    // tab-hopping never spotlights a hidden screen).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _index == i) {
        CoachMarks.maybeShow(context, _screenIds[i]);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Studio.bg,
      body: IndexedStack(
        index: _index,
        children: const [
          BooksScreen(),
          MetronomeScreen(),
          TunerScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: _BottomNav(index: _index, onTap: _select),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.index, required this.onTap});

  static const _items = [
    (Icons.library_music, 'Library'),
    (Icons.av_timer, 'Metronome'),
    (Icons.graphic_eq, 'Tuner'),
    (Icons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Studio.surface,
        border: Border(top: BorderSide(color: Studio.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: LayoutBuilder(
            builder: (context, c) {
              final itemW = c.maxWidth / _items.length;
              return Stack(
                children: [
                  // Sliding amber indicator across the top of the active tab.
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    left: index * itemW,
                    top: 0,
                    width: itemW,
                    height: 3,
                    child: Center(
                      child: Container(
                        width: 26,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Studio.amber,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: Studio.amber.withValues(alpha: 0.6),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < _items.length; i++)
                        Expanded(
                          child: _NavItem(
                            icon: _items[i].$1,
                            label: _items[i].$2,
                            active: i == index,
                            onTap: () => onTap(i),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? Studio.amber : Studio.textSecondary;
    return Pressable(
      onTap: onTap,
      child: Container(
        color: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: active ? 1.12 : 1,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: Studio.amber.withValues(alpha: 0.35),
                            blurRadius: 14,
                          ),
                        ]
                      : null,
                ),
                child: Icon(icon, color: color, size: 23),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.4,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
