import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Light tactile feedback (no-op where unsupported).
class Haptics {
  static void tap() => HapticFeedback.selectionClick();
  static void impact() => HapticFeedback.lightImpact();
}

/// "Studio" — a bespoke pro-audio design system. Amber accent, monospace
/// numeric readouts, fader-style controls, in a dark (default) or light skin.
/// Used on every platform for a unified look (not Material/Cupertino).

const String kAppVersion = '1.0.0';

/// One complete color skin. Values live here; the [Studio] facade exposes the
/// active palette so call sites keep the `Studio.x` syntax.
class StudioPalette {
  final Color bg, surface, surfaceHigh, line;
  final Color textPrimary, textSecondary, textDim;
  final Color amber, amberSoft, teal, red, green;
  final Color cardTop; // StudioCard gradient start
  final Color shadow; // StudioCard drop shadow
  final Color barrier; // dialog barrier
  final Color dim; // coach-mark scrim

  const StudioPalette.dark()
    : bg = const Color(0xFF0D0D0F),
      surface = const Color(0xFF161619),
      surfaceHigh = const Color(0xFF202026),
      line = const Color(0xFF2C2C33),
      textPrimary = const Color(0xFFF3F3F5),
      textSecondary = const Color(0xFF8E8E98),
      textDim = const Color(0xFF5C5C66),
      amber = const Color(0xFFFFB020),
      amberSoft = const Color(0x33FFB020),
      teal = const Color(0xFF35D0BA),
      red = const Color(0xFFFF5D5D),
      green = const Color(0xFF35D06A),
      cardTop = const Color(0xFF1A1A1F),
      shadow = const Color(0x33000000),
      barrier = const Color(0x99000000),
      dim = const Color(0xBF000000);

  const StudioPalette.light()
    : bg = const Color(0xFFF5F5F7),
      surface = const Color(0xFFFFFFFF),
      surfaceHigh = const Color(0xFFECECF0),
      line = const Color(0xFFDDDDE3),
      textPrimary = const Color(0xFF17171C),
      textSecondary = const Color(0xFF5F5F6A),
      textDim = const Color(0xFF9A9AA4),
      amber = const Color(0xFFB87F00), // darkened brand amber for contrast
      amberSoft = const Color(0x22B87F00),
      teal = const Color(0xFF0E8F7E),
      red = const Color(0xFFD54040),
      green = const Color(0xFF1B9E4B),
      cardTop = const Color(0xFFFFFFFF),
      shadow = const Color(0x14000000),
      barrier = const Color(0x61000000),
      dim = const Color(0xA6000000);
}

class Studio {
  static StudioPalette _p = const StudioPalette.dark();
  static bool _isDark = true;
  static bool get isDark => _isDark;

  /// Swap the active skin. The app root re-keys the tree afterwards so every
  /// widget re-reads these getters.
  static void setBrightness(Brightness b) {
    _isDark = b == Brightness.dark;
    _p = _isDark ? const StudioPalette.dark() : const StudioPalette.light();
  }

  // Palette (same call-site syntax as the old consts).
  static Color get bg => _p.bg;
  static Color get surface => _p.surface;
  static Color get surfaceHigh => _p.surfaceHigh;
  static Color get line => _p.line;
  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get textDim => _p.textDim;
  static Color get amber => _p.amber;
  static Color get amberSoft => _p.amberSoft;
  static Color get teal => _p.teal;
  static Color get red => _p.red;
  static Color get green => _p.green;
  static Color get cardTop => _p.cardTop;
  static Color get shadow => _p.shadow;
  static Color get barrier => _p.barrier;
  static Color get dim => _p.dim;

  // Bundled monospace for numeric readouts — identical on every platform.
  static const mono = TextStyle(
    fontFamily: 'JetBrainsMono',
    fontFamilyFallback: ['Menlo', 'Monaco', 'monospace'],
  );

  static TextStyle numeric(double size, {Color? color}) => mono.copyWith(
    fontSize: size,
    color: color ?? textPrimary,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );

  // Uppercase tracked label (section headers, units)
  static TextStyle get label => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
    color: textSecondary,
  );

  static TextStyle get title =>
      TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary);

  static TextStyle get body => TextStyle(fontSize: 14, color: textPrimary);
  static TextStyle get bodyDim => TextStyle(fontSize: 13, color: textSecondary);

  /// Slider theme that turns Material's Slider into a thin studio fader.
  static SliderThemeData sliderTheme({Color? accent}) {
    final a = accent ?? amber;
    return SliderThemeData(
      trackHeight: 3,
      activeTrackColor: a,
      inactiveTrackColor: line,
      thumbColor: a,
      overlayColor: a.withValues(alpha: 0.15),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      trackShape: const RoundedRectSliderTrackShape(),
    );
  }
}

/// App-wide ThemeData wrapping the active studio palette (so MaterialApp
/// routing / text infra works, but nothing reads as "Material").
ThemeData studioTheme() {
  final dark = Studio.isDark;
  final base = ThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    useMaterial3: true,
  );
  final scheme = dark
      ? ColorScheme.dark(
          surface: Studio.bg,
          primary: Studio.amber,
          secondary: Studio.teal,
          error: Studio.red,
        )
      : ColorScheme.light(
          surface: Studio.bg,
          primary: Studio.amber,
          secondary: Studio.teal,
          error: Studio.red,
        );
  return base.copyWith(
    scaffoldBackgroundColor: Studio.bg,
    canvasColor: Studio.bg,
    sliderTheme: Studio.sliderTheme(),
    colorScheme: scheme,
    textTheme:
        (dark ? Typography.whiteMountainView : Typography.blackMountainView)
            .apply(
              bodyColor: Studio.textPrimary,
              displayColor: Studio.textPrimary,
            ),
  );
}

// ───────────────────────── Components ─────────────────────────

/// Custom screen shell with a slim studio top bar (no Material AppBar).
class StudioScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget body;
  final Widget? bottomBar;
  final bool showBack;

  /// Optional decorative layer painted behind the whole scaffold (e.g. a
  /// blurred album cover in the player). Sits under the top bar and body.
  final Widget? backdrop;

  const StudioScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const [],
    this.bottomBar,
    this.showBack = false,
    this.backdrop,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        _TopBar(
          title: title,
          subtitle: subtitle,
          actions: actions,
          showBack: showBack,
        ),
        Expanded(
          child: DecoratedBox(
            // Soft amber glow bleeding down from the top for depth. When a
            // backdrop is present, skip the solid fill so it shows through.
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -1.2),
                radius: 1.4,
                colors: [
                  const Color(0x14FFB020),
                  backdrop == null ? Studio.bg : Colors.transparent,
                ],
                stops: const [0.0, 0.6],
              ),
            ),
            // No bottom bar → keep content clear of the home indicator.
            child: bottomBar == null ? SafeArea(top: false, child: body) : body,
          ),
        ),
        ?bottomBar,
      ],
    );
    return Scaffold(
      backgroundColor: Studio.bg,
      body: backdrop == null
          ? content
          : Stack(fit: StackFit.expand, children: [backdrop!, content]),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showBack;
  const _TopBar({
    required this.title,
    this.subtitle,
    required this.actions,
    required this.showBack,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      decoration: BoxDecoration(
        color: Studio.surface,
        border: Border(bottom: BorderSide(color: Studio.line)),
      ),
      // Background extends under the status bar; content sits below it.
      padding: EdgeInsets.only(top: topInset),
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (showBack)
                StudioIconButton(
                  icon: Icons.chevron_left,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              if (showBack) const SizedBox(width: 4),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Studio.amber,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: Studio.textPrimary,
                      ),
                    ),
                    if (subtitle case final s?)
                      Text(
                        s,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Studio.bodyDim.copyWith(fontSize: 11),
                      ),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

class StudioCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;
  const StudioCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: color == null
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Studio.cardTop, Studio.surface],
              )
            : null,
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Studio.line),
        boxShadow: [
          BoxShadow(
            color: Studio.shadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Pressable(onTap: onTap!, child: card);
  }
}

class SectionLabel extends StatelessWidget {
  final IconData? icon;
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.icon, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: Studio.amber),
          SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            text.toUpperCase(),
            style: Studio.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[Spacer(), trailing!],
      ],
    );
  }
}

class NumericReadout extends StatelessWidget {
  final String value;
  final String unit;
  final double size;
  final Color? color;
  const NumericReadout(
    this.value, {
    super.key,
    this.unit = '',
    this.size = 40,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Studio.textPrimary;
    final glow = c == Studio.amber || c == Studio.teal;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Animate the value in/out vertically when it changes (e.g. BPM).
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          transitionBuilder: (child, anim) => ClipRect(
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.35),
                end: Offset.zero,
              ).animate(anim),
              child: FadeTransition(opacity: anim, child: child),
            ),
          ),
          child: Text(
            value,
            key: ValueKey(value),
            style: Studio.numeric(size, color: c).copyWith(
              shadows: glow
                  ? [Shadow(color: c.withValues(alpha: 0.5), blurRadius: 16)]
                  : null,
            ),
          ),
        ),
        if (unit.isNotEmpty)
          Text(unit.toUpperCase(), style: Studio.label.copyWith(fontSize: 10)),
      ],
    );
  }
}

/// Animated 3-bar equalizer, shown next to the currently-playing track.
class EqualizerBars extends StatefulWidget {
  final Color? color;
  final double size;
  final bool active;
  const EqualizerBars({
    super.key,
    this.color,
    this.size = 16,
    this.active = true,
  });

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return SizedBox(width: widget.size, height: widget.size);
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          double bar(double phase) {
            final v =
                (0.5 + 0.5 * (1 - (((_c.value + phase) % 1) - 0.5).abs() * 2));
            return widget.size * (0.3 + 0.7 * v);
          }

          Widget b(double h) => Container(
            width: widget.size * 0.22,
            height: h,
            decoration: BoxDecoration(
              color: widget.color ?? Studio.amber,
              borderRadius: BorderRadius.circular(1),
            ),
          );
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [b(bar(0)), b(bar(0.33)), b(bar(0.66))],
          );
        },
      ),
    );
  }
}

enum StudioButtonKind { filled, ghost, outline }

class StudioButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final StudioButtonKind kind;
  final Color? accent;
  const StudioButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.kind = StudioButtonKind.filled,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    late Color bg, fg, border;
    switch (kind) {
      case StudioButtonKind.filled:
        bg = accent ?? Studio.amber;
        fg = Studio.bg;
        border = accent ?? Studio.amber;
      case StudioButtonKind.ghost:
        bg = Studio.surfaceHigh;
        fg = Studio.textPrimary;
        border = Studio.surfaceHigh;
      case StudioButtonKind.outline:
        bg = Colors.transparent;
        fg = accent ?? Studio.amber;
        border = Studio.line;
    }
    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: Pressable(
        onTap: onTap ?? () {},
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StudioIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  final String? tooltip;
  const StudioIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 22,
    this.color,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Pressable(
      onTap: onTap ?? () {},
      child: Opacity(
        opacity: onTap == null ? 0.35 : 1,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: size, color: color ?? Studio.textPrimary),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: btn) : btn;
  }
}

/// A pill-style segmented control (e.g. speed presets).
class StudioSegmented<T> extends StatelessWidget {
  final List<(T value, String label)> options;
  final T selected;
  final ValueChanged<T> onChanged;
  const StudioSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Studio.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Studio.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, label) in options)
            Pressable(
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: value == selected ? Studio.amber : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  style: Studio.numeric(
                    13,
                    color: value == selected ? Studio.bg : Studio.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Custom on/off toggle (amber when on) — not a Material Switch.
class StudioSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const StudioSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 44,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? Studio.amber : Studio.surfaceHigh,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: value ? Studio.amber : Studio.line),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: value ? Studio.bg : Studio.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Lightweight press-scale feedback without Material ink.
/// Tap target with press-scale feedback + light haptic. Reusable everywhere.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool haptic;
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.haptic = true,
  });

  @override
  State<Pressable> createState() => PressableState();
}

class PressableState extends State<Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: () {
          if (widget.haptic) Haptics.tap();
          widget.onTap();
        },
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                setState(() => _down = false);
                if (widget.haptic) Haptics.impact();
                widget.onLongPress!();
              },
        child: AnimatedScale(
          scale: _down ? 0.96 : 1,
          duration: const Duration(milliseconds: 90),
          child: widget.child,
        ),
      ),
    );
  }
}

// ───────────────────────── Dialogs & menus ─────────────────────────

class StudioMenuAction {
  final String label;
  final IconData? icon;
  final bool destructive;
  final VoidCallback onTap;
  const StudioMenuAction(
    this.label, {
    required this.onTap,
    this.icon,
    this.destructive = false,
  });
}

Future<void> showStudioMenu(
  BuildContext context, {
  String? title,
  required List<StudioMenuAction> actions,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => Container(
      margin: const EdgeInsets.all(10),
      // Cap the height so long menus (e.g. time signatures) scroll instead of
      // overflowing.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(ctx).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: Studio.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Studio.line),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(title.toUpperCase(), style: Studio.label),
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final a in actions)
                      Pressable(
                        onTap: () {
                          Navigator.pop(ctx);
                          a.onTap();
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              if (a.icon != null) ...[
                                Icon(
                                  a.icon,
                                  size: 19,
                                  color: a.destructive
                                      ? Studio.red
                                      : Studio.textPrimary,
                                ),
                                const SizedBox(width: 12),
                              ],
                              Text(
                                a.label,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: a.destructive
                                      ? Studio.red
                                      : Studio.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool> studioConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'OK',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: Studio.barrier,
    builder: (ctx) => _DialogShell(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Text(message, style: Studio.bodyDim),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              StudioButton(
                label: 'Cancel',
                kind: StudioButtonKind.ghost,
                onTap: () => Navigator.pop(ctx, false),
              ),
              const SizedBox(width: 10),
              StudioButton(
                label: confirmLabel,
                accent: destructive ? Studio.red : Studio.amber,
                onTap: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return ok ?? false;
}

Future<String?> studioPrompt(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    barrierColor: Studio.barrier,
    builder: (ctx) => _DialogShell(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            cursorColor: Studio.amber,
            style: Studio.body,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: Studio.bodyDim,
              filled: true,
              fillColor: Studio.surfaceHigh,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Studio.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Studio.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Studio.amber),
              ),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              StudioButton(
                label: 'Cancel',
                kind: StudioButtonKind.ghost,
                onTap: () => Navigator.pop(ctx),
              ),
              const SizedBox(width: 10),
              StudioButton(
                label: 'Save',
                onTap: () => Navigator.pop(ctx, controller.text),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Brief, non-blocking studio-styled toast.
void showToast(BuildContext context, String message) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      bottom: 60,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              color: Studio.surfaceHigh,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Studio.line),
            ),
            child: Text(message, style: Studio.body),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Future.delayed(const Duration(seconds: 2), entry.remove);
}

class _DialogShell extends StatelessWidget {
  final String title;
  final Widget child;
  const _DialogShell({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Container(
          width: 380,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Studio.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Studio.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Studio.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// A studio-styled slider (thin track + amber thumb).
class StudioSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final Color? accent;
  const StudioSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: Studio.sliderTheme(accent: accent ?? Studio.amber),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: onChanged,
      ),
    );
  }
}
