import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Independent metronome: ticks at a set BPM alongside the music, with its own
/// volume/mute. Emits a beat event stream that the visual widget animates to.
///
/// Uses `audioplayers` (purpose-built for short, rapidly-repeated SFX) rather
/// than just_audio, which is tuned for long-form playback and is unreliable at
/// re-triggering a tiny click many times per second.
class Metronome extends ChangeNotifier {
  // Two preloaded players so the accented downbeat and the normal beat can
  // fire back-to-back without reloading an asset.
  final AudioPlayer _accent = AudioPlayer();
  final AudioPlayer _click = AudioPlayer();
  final _accentSrc = AssetSource('sounds/accent.wav');
  final _clickSrc = AssetSource('sounds/click.wav');

  final _beatController = StreamController<int>.broadcast();

  /// Fires the current beat index (0-based) on every tick.
  Stream<int> get beatStream => _beatController.stream;

  int _bpm = 80;
  int get bpm => _bpm;

  int _beatsPerBar = 4;
  int get beatsPerBar => _beatsPerBar;

  double _volume = 0.8;
  double get volume => _volume;

  bool _muted = false;
  bool get muted => _muted;

  bool _visualEnabled = true;
  bool get visualEnabled => _visualEnabled;

  // Manual sync offset in milliseconds: shifts the click grid relative to the
  // music. Positive = click later, negative = click earlier.
  int _syncOffsetMs = 0;
  int get syncOffsetMs => _syncOffsetMs;

  bool _running = false;
  bool get running => _running;

  bool _paused = false;
  bool get paused => _paused;

  // Playback speed multiplier (1.0 = normal). Scales the click rate so it stays
  // locked to the sped-up/slowed music.
  double _speed = 1.0;
  double get speed => _speed;

  int _currentBeat = 0;
  int get currentBeat => _currentBeat;

  Timer? _timer;
  final Stopwatch _sw = Stopwatch();
  int _nextBeatUs = 0;

  // Tap-tempo state
  final List<int> _taps = [];

  Future<void> init() async {
    try {
      for (final pl in [_accent, _click]) {
        await pl.setReleaseMode(ReleaseMode.stop); // keep source ready for replay
      }
      // Warm up the sources so the first click has no load delay.
      await _accent.setSource(_accentSrc);
      await _click.setSource(_clickSrc);
    } catch (e) {
      debugPrint('Metronome init error: $e');
    }
  }

  void start() {
    if (_running) return;
    _running = true;
    _beginFromDownbeat();
    notifyListeners();
  }

  /// Re-lock to beat 1 (downbeat) — used when the track loops back to the start
  /// so the click re-aligns with the music's restart.
  void restartFromDownbeat() {
    if (!_running) return;
    _beginFromDownbeat();
    notifyListeners();
  }

  /// Microseconds between beats at the current tempo and speed.
  int _intervalUs() => (60000000 / (_bpm * _speed)).round();

  void _beginFromDownbeat() {
    _paused = false;
    _currentBeat = -1;
    _timer?.cancel();
    _sw
      ..reset()
      ..start();
    // Apply the sync offset to the first beat's timing. A negative offset is
    // wrapped forward by one beat so we never schedule in the past.
    final intervalUs = _intervalUs();
    int firstUs = _syncOffsetMs * 1000;
    while (firstUs < 0) {
      firstUs += intervalUs;
    }
    _nextBeatUs = firstUs;
    _timer = Timer(Duration(microseconds: firstUs), _tick);
  }

  /// Freeze the click at its exact current phase (used when the music pauses).
  /// Resuming continues from the same beat position so they stay in sync.
  void pause() {
    if (!_running || _paused) return;
    _paused = true;
    _timer?.cancel();
    _timer = null;
    _sw.stop(); // freeze elapsed time — preserves how far we are into the beat
    notifyListeners();
  }

  /// Continue from the frozen phase set by [pause].
  void resume() {
    if (!_running || !_paused) return;
    _paused = false;
    _sw.start(); // elapsed time continues from where it froze
    final delayUs = _nextBeatUs - _sw.elapsedMicroseconds;
    _timer = Timer(
      Duration(microseconds: delayUs < 0 ? 0 : delayUs),
      _tick,
    );
    notifyListeners();
  }

  void stop() {
    _running = false;
    _paused = false;
    _timer?.cancel();
    _timer = null;
    _sw.stop();
    notifyListeners();
  }

  void toggle() => _running ? stop() : start();

  void _tick() {
    if (!_running) return;
    _currentBeat = (_currentBeat + 1) % _beatsPerBar;
    _fireBeat(_currentBeat);

    _nextBeatUs += _intervalUs();
    final delayUs = _nextBeatUs - _sw.elapsedMicroseconds;
    _timer = Timer(
      Duration(microseconds: delayUs < 0 ? 0 : delayUs),
      _tick,
    );
  }

  void _fireBeat(int beat) {
    if (!_muted) {
      final pl = beat == 0 ? _accent : _click;
      final src = beat == 0 ? _accentSrc : _clickSrc;
      // Replay the preloaded click from the start. play() restarts cleanly even
      // if the previous click is still ringing out.
      pl.play(src, volume: _volume).catchError(
            (e) => debugPrint('click error: $e'),
          );
    }
    _beatController.add(beat);
    notifyListeners();
  }

  void setBpm(int value) {
    _bpm = value.clamp(20, 300);
    notifyListeners();
  }

  void nudgeBpm(int delta) => setBpm(_bpm + delta);

  void setBeatsPerBar(int value) {
    _beatsPerBar = value.clamp(1, 16);
    if (_currentBeat >= _beatsPerBar) _currentBeat = 0;
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0);
    await _applyVolume();
    notifyListeners();
  }

  Future<void> toggleMute() async {
    _muted = !_muted;
    await _applyVolume();
    notifyListeners();
  }

  void setVisualEnabled(bool v) {
    _visualEnabled = v;
    notifyListeners();
  }

  /// Shift the click relative to the music. Takes effect live while running, so
  /// the user can drag the slider and hear the click move into alignment.
  void setSyncOffset(int ms) {
    final clamped = ms.clamp(-1000, 1000);
    final deltaUs = (clamped - _syncOffsetMs) * 1000;
    _syncOffsetMs = clamped;
    if (_running) {
      _nextBeatUs += deltaUs;
      // Only reschedule the ticking timer when actively running (not paused).
      if (!_paused) {
        _timer?.cancel();
        final delayUs = _nextBeatUs - _sw.elapsedMicroseconds;
        _timer = Timer(
          Duration(microseconds: delayUs < 0 ? 0 : delayUs),
          _tick,
        );
      }
    }
    notifyListeners();
  }

  void nudgeSyncOffset(int deltaMs) => setSyncOffset(_syncOffsetMs + deltaMs);

  /// Set the playback-speed multiplier. While running, re-locks to the downbeat
  /// so the new tempo applies cleanly.
  void setSpeed(double value) {
    final v = value <= 0 ? 1.0 : value;
    if (v == _speed) return;
    _speed = v;
    if (_running && !_paused) {
      _beginFromDownbeat();
    }
    notifyListeners();
  }

  Future<void> _applyVolume() async {
    // Volume is also passed per-play in _fireBeat; this keeps any currently
    // ringing click in sync when the user drags the slider.
    final v = _muted ? 0.0 : _volume;
    await _accent.setVolume(v);
    await _click.setVolume(v);
  }

  /// Register a tap; once we have a couple, derive BPM from the average gap.
  void tap() {
    final now = DateTime.now().microsecondsSinceEpoch;
    if (_taps.isNotEmpty && now - _taps.last > 2000000) {
      _taps.clear(); // reset if the user paused too long
    }
    _taps.add(now);
    if (_taps.length > 6) _taps.removeAt(0);
    if (_taps.length >= 2) {
      int sum = 0;
      for (var i = 1; i < _taps.length; i++) {
        sum += _taps[i] - _taps[i - 1];
      }
      final avgUs = sum / (_taps.length - 1);
      if (avgUs > 0) setBpm((60000000 / avgUs).round());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _beatController.close();
    _accent.dispose();
    _click.dispose();
    super.dispose();
  }
}
