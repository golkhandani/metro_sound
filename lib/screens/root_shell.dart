import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/tuner.dart';
import '../ui/studio.dart';
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
  int _index = 0;
  static const _tunerTab = 2;

  void _select(int i) {
    if (i == _index) {
      return;
    }
    final tuner = context.read<Tuner>();
    setState(() => _index = i);
    // Run the mic only while the Tuner tab is showing.
    if (i == _tunerTab) {
      tuner.start();
    } else {
      tuner.stop();
    }
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
      decoration: const BoxDecoration(
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
                                blurRadius: 8),
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
                              blurRadius: 14)
                        ]
                      : null,
                ),
                child: Icon(icon, color: color, size: 23),
              ),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.4,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: color)),
          ],
        ),
      ),
    );
  }
}
