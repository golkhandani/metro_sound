import 'package:flutter/material.dart';

/// "Dark Studio" — a bespoke pro-audio design system. Near-black surfaces,
/// amber accent, monospace numeric readouts, fader-style controls. Used on
/// every platform for a unified look (not Material/Cupertino).

const String kAppVersion = '1.0.0';

class Studio {
  // Palette
  static const bg = Color(0xFF0D0D0F);
  static const surface = Color(0xFF161619);
  static const surfaceHigh = Color(0xFF202026);
  static const line = Color(0xFF2C2C33);
  static const textPrimary = Color(0xFFF3F3F5);
  static const textSecondary = Color(0xFF8E8E98);
  static const textDim = Color(0xFF5C5C66);
  static const amber = Color(0xFFFFB020);
  static const amberSoft = Color(0x33FFB020);
  static const teal = Color(0xFF35D0BA);
  static const red = Color(0xFFFF5D5D);

  // Monospace family for numeric readouts (Menlo/Monaco ship on macOS/iOS).
  static const mono = TextStyle(
    fontFamilyFallback: ['Menlo', 'Monaco', 'Roboto Mono', 'monospace'],
  );

  static TextStyle numeric(double size, {Color color = textPrimary}) =>
      mono.copyWith(
          fontSize: size,
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5);

  // Uppercase tracked label (section headers, units)
  static const label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
    color: textSecondary,
  );

  static const title = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const body = TextStyle(fontSize: 14, color: textPrimary);
  static const bodyDim = TextStyle(fontSize: 13, color: textSecondary);

  /// Slider theme that turns Material's Slider into a thin studio fader.
  static SliderThemeData sliderTheme({Color accent = amber}) => SliderThemeData(
        trackHeight: 3,
        activeTrackColor: accent,
        inactiveTrackColor: line,
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.15),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        trackShape: const RoundedRectSliderTrackShape(),
      );
}

/// App-wide ThemeData wrapping the studio palette (so MaterialApp routing /
/// text infra works, but nothing reads as "Material").
ThemeData studioTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Studio.bg,
    canvasColor: Studio.bg,
    sliderTheme: Studio.sliderTheme(),
    colorScheme: const ColorScheme.dark(
      surface: Studio.bg,
      primary: Studio.amber,
      secondary: Studio.teal,
      error: Studio.red,
    ),
    textTheme: Typography.whiteMountainView.apply(
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

  const StudioScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const [],
    this.bottomBar,
    this.showBack = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Studio.bg,
      body: Column(
        children: [
          _TopBar(
              title: title,
              subtitle: subtitle,
              actions: actions,
              showBack: showBack),
          Expanded(
            child: DecoratedBox(
              // Soft amber glow bleeding down from the top for depth.
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -1.2),
                  radius: 1.4,
                  colors: [Color(0x14FFB020), Studio.bg],
                  stops: [0.0, 0.6],
                ),
              ),
              child: body,
            ),
          ),
          ?bottomBar,
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showBack;
  const _TopBar(
      {required this.title,
      this.subtitle,
      required this.actions,
      required this.showBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: Studio.surface,
        border: Border(bottom: BorderSide(color: Studio.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (showBack)
              StudioIconButton(
                icon: Icons.chevron_left,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            if (showBack) const SizedBox(width: 4),
            Container(width: 8, height: 8, decoration: const BoxDecoration(
                color: Studio.amber, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: Studio.textPrimary)),
                  if (subtitle case final s?)
                    Text(s,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Studio.bodyDim.copyWith(fontSize: 11)),
                ],
              ),
            ),
            ...actions,
          ],
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
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1A1A1F), Studio.surface],
              )
            : null,
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Studio.line),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return _Pressable(onTap: onTap!, child: card);
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
          const SizedBox(width: 8),
        ],
        Text(text.toUpperCase(), style: Studio.label),
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

class NumericReadout extends StatelessWidget {
  final String value;
  final String unit;
  final double size;
  final Color color;
  const NumericReadout(this.value,
      {super.key,
      this.unit = '',
      this.size = 40,
      this.color = Studio.textPrimary});

  @override
  Widget build(BuildContext context) {
    final glow = color == Studio.amber || color == Studio.teal;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: Studio.numeric(size, color: color).copyWith(
              shadows: glow
                  ? [Shadow(color: color.withValues(alpha: 0.5), blurRadius: 16)]
                  : null,
            )),
        if (unit.isNotEmpty)
          Text(unit.toUpperCase(),
              style: Studio.label.copyWith(fontSize: 10)),
      ],
    );
  }
}

/// Animated 3-bar equalizer, shown next to the currently-playing track.
class EqualizerBars extends StatefulWidget {
  final Color color;
  final double size;
  final bool active;
  const EqualizerBars(
      {super.key, this.color = Studio.amber, this.size = 16, this.active = true});

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
        ..repeat(reverse: true);

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
            final v = (0.5 + 0.5 * (1 - (((_c.value + phase) % 1) - 0.5).abs() * 2));
            return widget.size * (0.3 + 0.7 * v);
          }

          Widget b(double h) => Container(
                width: widget.size * 0.22,
                height: h,
                decoration: BoxDecoration(
                  color: widget.color,
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
  final Color accent;
  const StudioButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.kind = StudioButtonKind.filled,
    this.accent = Studio.amber,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    late Color bg, fg, border;
    switch (kind) {
      case StudioButtonKind.filled:
        bg = accent;
        fg = Studio.bg;
        border = accent;
      case StudioButtonKind.ghost:
        bg = Studio.surfaceHigh;
        fg = Studio.textPrimary;
        border = Studio.surfaceHigh;
      case StudioButtonKind.outline:
        bg = Colors.transparent;
        fg = accent;
        border = Studio.line;
    }
    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: _Pressable(
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
              Text(label,
                  style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3)),
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
    final btn = _Pressable(
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
            _Pressable(
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: value == selected ? Studio.amber : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(label,
                    style: Studio.numeric(13,
                        color: value == selected
                            ? Studio.bg
                            : Studio.textSecondary)),
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
    return _Pressable(
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
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _Pressable({required this.child, required this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
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
  const StudioMenuAction(this.label,
      {required this.onTap, this.icon, this.destructive = false});
}

Future<void> showStudioMenu(BuildContext context,
    {String? title, required List<StudioMenuAction> actions}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      margin: const EdgeInsets.all(10),
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
                    child: Text(title.toUpperCase(), style: Studio.label)),
              ),
            for (final a in actions)
              _Pressable(
                onTap: () {
                  Navigator.pop(ctx);
                  a.onTap();
                },
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      if (a.icon != null) ...[
                        Icon(a.icon,
                            size: 19,
                            color: a.destructive
                                ? Studio.red
                                : Studio.textPrimary),
                        const SizedBox(width: 12),
                      ],
                      Text(a.label,
                          style: TextStyle(
                              fontSize: 15,
                              color: a.destructive
                                  ? Studio.red
                                  : Studio.textPrimary)),
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

Future<bool> studioConfirm(BuildContext context,
    {required String title,
    String? message,
    String confirmLabel = 'OK',
    bool destructive = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
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
                  onTap: () => Navigator.pop(ctx, false)),
              const SizedBox(width: 10),
              StudioButton(
                  label: confirmLabel,
                  accent: destructive ? Studio.red : Studio.amber,
                  onTap: () => Navigator.pop(ctx, true)),
            ],
          ),
        ],
      ),
    ),
  );
  return ok ?? false;
}

Future<String?> studioPrompt(BuildContext context,
    {required String title, String initial = '', String hint = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
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
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Studio.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Studio.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Studio.amber),
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
                  onTap: () => Navigator.pop(ctx)),
              const SizedBox(width: 10),
              StudioButton(
                  label: 'Save',
                  onTap: () => Navigator.pop(ctx, controller.text)),
            ],
          ),
        ],
      ),
    ),
  );
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
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Studio.textPrimary)),
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
  final Color accent;
  const StudioSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.accent = Studio.amber,
  });

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: Studio.sliderTheme(accent: accent),
      child: Slider(
          value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
    );
  }
}
