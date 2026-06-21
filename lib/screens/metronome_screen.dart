import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/metronome.dart';
import '../ui/studio.dart';
import '../widgets/metronome_visual.dart';

/// Standalone metronome page (separate from the player). Uses the shared
/// metronome engine. Stops the click when you leave the page.
class MetronomeScreen extends StatefulWidget {
  const MetronomeScreen({super.key});

  @override
  State<MetronomeScreen> createState() => _MetronomeScreenState();
}

class _MetronomeScreenState extends State<MetronomeScreen> {
  Metronome? _metro;

  static const _timeSigs = [
    (2, 4), (3, 4), (4, 4), (5, 4), (6, 4), (7, 4),
    (2, 2), (3, 8), (5, 8), (6, 8), (7, 8), (9, 8), (12, 8),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _metro = context.read<Metronome>();
  }

  @override
  void dispose() {
    _metro?.stop();
    super.dispose();
  }

  void _timeSig(Metronome m) {
    showStudioMenu(context, title: 'Time signature', actions: [
      for (final (n, d) in _timeSigs)
        StudioMenuAction('$n / $d', onTap: () => m.setTimeSignature(n, d)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final m = context.watch<Metronome>();

    return StudioScaffold(
      title: 'Metronome',
      subtitle: m.timeSigLabel,
      showBack: true,
      actions: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text('VISUAL', style: Studio.label.copyWith(fontSize: 10)),
          const SizedBox(width: 6),
          StudioSwitch(value: m.visualEnabled, onChanged: m.setVisualEnabled),
          const SizedBox(width: 8),
        ]),
      ],
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (m.visualEnabled) ...[
            const SizedBox(height: 8),
            Center(child: MetronomeVisual(metronome: m)),
            const SizedBox(height: 10),
          ],
          Center(child: BeatIndicator(metronome: m)),
          const SizedBox(height: 24),
          // BPM readout + steppers
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Stepper(icon: Icons.remove, onTap: () => m.nudgeBpm(-1)),
              const SizedBox(width: 28),
              NumericReadout('${m.bpm}', unit: 'BPM', size: 64),
              const SizedBox(width: 28),
              _Stepper(icon: Icons.add, onTap: () => m.nudgeBpm(1)),
            ],
          ),
          const SizedBox(height: 8),
          StudioSlider(
            min: 20,
            max: 300,
            value: m.bpm.toDouble(),
            onChanged: (v) => m.setBpm(v.round()),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              StudioButton(
                  label: 'Tap',
                  icon: Icons.touch_app_outlined,
                  kind: StudioButtonKind.ghost,
                  onTap: m.tap),
              StudioButton(
                  label: m.timeSigLabel,
                  kind: StudioButtonKind.ghost,
                  onTap: () => _timeSig(m)),
            ],
          ),
          const SizedBox(height: 28),
          // Big start/stop
          Center(child: _StartButton(running: m.running, onTap: m.toggle)),
          const SizedBox(height: 28),
          // Volume
          _VolumeFader(metronome: m),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _Stepper({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Studio.surfaceHigh,
            shape: BoxShape.circle,
            border: Border.all(color: Studio.line),
          ),
          child: Icon(icon, color: Studio.amber, size: 24),
        ),
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  final bool running;
  final VoidCallback onTap;
  const _StartButton({required this.running, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: running ? Studio.surfaceHigh : Studio.amber,
            shape: BoxShape.circle,
            border: Border.all(
                color: running ? Studio.amber : Colors.transparent, width: 2),
            boxShadow: [
              BoxShadow(
                  color: Studio.amber.withValues(alpha: running ? 0.0 : 0.4),
                  blurRadius: 22,
                  spreadRadius: 2),
            ],
          ),
          child: Icon(running ? Icons.stop : Icons.play_arrow,
              color: running ? Studio.amber : Studio.bg, size: 46),
        ),
      ),
    );
  }
}

class _VolumeFader extends StatelessWidget {
  final Metronome metronome;
  const _VolumeFader({required this.metronome});

  @override
  Widget build(BuildContext context) {
    final muted = metronome.muted;
    return Row(
      children: [
        StudioIconButton(
            icon: muted ? Icons.volume_off : Icons.volume_up,
            size: 20,
            color: muted ? Studio.red : Studio.amber,
            onTap: metronome.toggleMute),
        SizedBox(width: 72, child: Text('Volume', style: Studio.body)),
        Expanded(
          child: StudioSlider(
            value: muted ? 0 : metronome.volume,
            onChanged: muted ? null : metronome.setVolume,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text('${(metronome.volume * 100).round()}',
              textAlign: TextAlign.end,
              style: Studio.numeric(12, color: Studio.textSecondary)),
        ),
      ],
    );
  }
}
