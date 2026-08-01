import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/audio_controller.dart';
import '../services/metronome.dart';

/// Holds the screen awake while the user is actively practicing — i.e. whenever
/// the metronome is ticking or a track is playing. The auto-lock timer would
/// otherwise dim and lock the screen mid-exercise, which is exactly when the
/// player needs to keep glancing at the tempo, pendulum, or sheet photo.
///
/// Renders nothing; it just watches the two playback services and toggles the
/// OS wakelock as their combined "is anything running" state changes. Mount it
/// once, high in the tree, below the providers.
class KeepAwake extends StatefulWidget {
  final Widget child;
  const KeepAwake({super.key, required this.child});

  @override
  State<KeepAwake> createState() => _KeepAwakeState();
}

class _KeepAwakeState extends State<KeepAwake> {
  bool _awake = false;

  @override
  Widget build(BuildContext context) {
    // Rebuilds whenever either service notifies (start/stop/pause/play).
    final metroActive = context.select<Metronome, bool>(
      (m) => m.running && !m.paused,
    );
    final musicPlaying = context.select<AudioController, bool>(
      (a) => a.isPlaying,
    );
    _apply(metroActive || musicPlaying);
    return widget.child;
  }

  void _apply(bool shouldStayAwake) {
    if (shouldStayAwake == _awake) return;
    _awake = shouldStayAwake;
    // Fire-and-forget: the platform channel is idempotent and we only call it
    // on transitions, so races between rapid start/stop toggles settle to the
    // last requested state.
    WakelockPlus.toggle(enable: shouldStayAwake);
  }

  @override
  void dispose() {
    // Never leave the wakelock held once this leaves the tree.
    if (_awake) WakelockPlus.disable();
    super.dispose();
  }
}
