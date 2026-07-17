import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  int _beatsPerBar = 4; // numerator = number of clicks per bar
  int get beatsPerBar => _beatsPerBar;

  int _denominator = 4; // note value (4, 8, 2…) — for display + accent grouping
  int get denominator => _denominator;

  String get timeSigLabel => '$_beatsPerBar/$_denominator';

  // Which beat indices get the accented (downbeat) click.
  Set<int> _accents = {0};

  double _volume = 0.8;
  double get volume => _volume;

  bool _muted = false;
  bool get muted => _muted;

  bool _visualEnabled = true;
  bool get visualEnabled => _visualEnabled;

  // Lock-to-music: derive each beat from the music's playback position so the
  // click can never drift from the recording, and scrubbing the waveform moves
  // the click with it. On by default. Falls back to free-running when no music
  // is playing (e.g. the standalone metronome screen).
  bool _locked = true;
  bool get lockedToMusic => _locked;

  // The music clock, injected by the player via [bindMusicClock]. Kept as plain
  // callbacks so this service doesn't depend on the audio layer.
  int Function()? _musicPosMs;
  bool Function()? _musicPlaying;

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

  // Lock-mode polling state.
  Timer? _lockTimer;
  int _lockLastIdx = 0;
  bool _lockPrimed = false;
  bool _inFallback = false;

  // Tap-tempo state
  final List<int> _taps = [];

  // Persisted preferences (visual + lock).
  File? _prefsFile;

  /// The cooperative playback session shared with the just_audio music player:
  /// mix with other audio on iOS, take no audio focus on Android.
  static AudioContext get _playbackContext => AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.none,
        ),
      );

  /// Re-assert the playback session. The tuner (and recorder) switch the
  /// shared iOS session into a record category, which lowers playback volume;
  /// call this after they stop so music/click volume comes back.
  Future<void> restorePlaybackSession() async {
    try {
      await AudioPlayer.global.setAudioContext(_playbackContext);
    } catch (e) {
      debugPrint('restorePlaybackSession: $e');
    }
  }

  Future<void> init() async {
    try {
      // The clicks share one audio session with the just_audio music player.
      // audioplayers' DEFAULT context takes exclusive playback focus, so every
      // click (re)activated the session against the music — metronome use
      // audibly disturbed other audio. Make the click players cooperative.
      await AudioPlayer.global.setAudioContext(_playbackContext);
      for (final pl in [_accent, _click]) {
        await pl.setReleaseMode(
          ReleaseMode.stop,
        ); // keep source ready for replay
      }
      // Warm up the sources so the first click has no load delay.
      await _accent.setSource(_accentSrc);
      await _click.setSource(_clickSrc);
    } catch (e) {
      debugPrint('Metronome init error: $e');
    }
    // Load saved toggle preferences (defaults: both on).
    try {
      final dir = await getApplicationSupportDirectory();
      _prefsFile = File(p.join(dir.path, 'metronome.json'));
      if (await _prefsFile!.exists()) {
        final j =
            jsonDecode(await _prefsFile!.readAsString())
                as Map<String, dynamic>;
        if (j['visual'] is bool) _visualEnabled = j['visual'] as bool;
        if (j['lock'] is bool) _locked = j['lock'] as bool;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Metronome prefs load error: $e');
    }
  }

  Future<void> _savePrefs() async {
    try {
      await _prefsFile?.writeAsString(
        jsonEncode({'visual': _visualEnabled, 'lock': _locked}),
      );
    } catch (_) {}
  }

  void start() {
    if (_running) return;
    _running = true;
    if (_locked) {
      _lockArm();
    } else {
      _beginFromDownbeat();
    }
    notifyListeners();
  }

  /// Re-lock to beat 1 (downbeat) — used when the track loops back to the start
  /// so the click re-aligns with the music's restart.
  void restartFromDownbeat() {
    if (!_running) return;
    if (_locked) {
      _lockArm();
    } else {
      _beginFromDownbeat();
    }
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

  /// Inject the music clock so lock-mode can read the track's live position.
  void bindMusicClock({
    required int Function() positionMs,
    required bool Function() playing,
  }) {
    _musicPosMs = positionMs;
    _musicPlaying = playing;
  }

  void setLockedToMusic(bool v) {
    if (v == _locked) return;
    _locked = v;
    // Switch engines live if we're currently ticking.
    if (_running && !_paused) {
      if (v) {
        _timer?.cancel();
        _timer = null;
        _sw.stop();
        _lockArm();
      } else {
        _lockCancel();
        _beginFromDownbeat();
      }
    }
    notifyListeners();
    _savePrefs();
  }

  // One beat lasts this many milliseconds of *track* time (independent of
  // playback speed — sped-up audio simply reaches each beat sooner).
  double _beatMsTrack() => 60000.0 / (_bpm <= 0 ? 1 : _bpm);

  // Absolute beat index (…,-1,0,1,2,…) the given music position falls in.
  int _boundaryIndex(double posMs) =>
      ((posMs - _syncOffsetMs) / _beatMsTrack()).floor();

  int _beatInBar(int idx) =>
      ((idx % _beatsPerBar) + _beatsPerBar) % _beatsPerBar;

  void _lockArm() {
    _lockCancel();
    _paused = false;
    _lockPrimed = false;
    _inFallback = false;
    // Poll the (interpolated) music position frequently and click when we cross
    // a beat boundary.
    _lockTimer = Timer.periodic(
      const Duration(milliseconds: 10),
      (_) => _lockPoll(),
    );
  }

  void _lockCancel() {
    _lockTimer?.cancel();
    _lockTimer = null;
  }

  void _lockPoll() {
    if (!_running || _paused) return;
    final playing = _musicPlaying?.call() ?? false;
    if (playing) {
      _inFallback = false;
      final pos = (_musicPosMs?.call() ?? 0).toDouble();
      final idx = _boundaryIndex(pos);
      if (!_lockPrimed) {
        // First read: adopt the current beat without replaying everything we
        // may have scrolled past. Click straight away only if we're sitting
        // right at a boundary (so a play-from-start downbeat isn't skipped).
        _lockPrimed = true;
        _lockLastIdx = idx;
        _currentBeat = _beatInBar(idx);
        final into = (pos - _syncOffsetMs) - idx * _beatMsTrack();
        if (into <= _beatMsTrack() * 0.18) {
          _fireBeat(_currentBeat);
        } else {
          notifyListeners();
        }
        return;
      }
      if (idx != _lockLastIdx) {
        final forward = idx == _lockLastIdx + 1;
        _lockLastIdx = idx;
        _currentBeat = _beatInBar(idx);
        if (forward) {
          _fireBeat(_currentBeat);
        } else {
          // A jump (seek/scrub/loop) — realign silently, don't machine-gun.
          notifyListeners();
        }
      }
    } else {
      // No music playing: free-run off the clock so the standalone metronome
      // still works while lock-mode is on.
      _lockPrimed = false;
      if (!_inFallback) {
        _inFallback = true;
        _sw
          ..reset()
          ..start();
        _nextBeatUs = _intervalUs();
        _currentBeat = -1;
      }
      if (_sw.elapsedMicroseconds >= _nextBeatUs) {
        _currentBeat = (_currentBeat + 1) % _beatsPerBar;
        _fireBeat(_currentBeat);
        _nextBeatUs += _intervalUs();
      }
    }
  }

  /// Freeze the click at its exact current phase (used when the music pauses).
  /// Resuming continues from the same beat position so they stay in sync.
  void pause() {
    if (!_running || _paused) return;
    _paused = true;
    if (_locked) {
      _lockCancel();
    } else {
      _timer?.cancel();
      _timer = null;
      _sw.stop(); // freeze elapsed time — preserves how far we are into the beat
    }
    notifyListeners();
  }

  /// Continue from the frozen phase set by [pause].
  void resume() {
    if (!_running || !_paused) return;
    _paused = false;
    if (_locked) {
      _lockArm(); // re-derives phase from the music position
    } else {
      _sw.start(); // elapsed time continues from where it froze
      final delayUs = _nextBeatUs - _sw.elapsedMicroseconds;
      _timer = Timer(Duration(microseconds: delayUs < 0 ? 0 : delayUs), _tick);
    }
    notifyListeners();
  }

  void stop() {
    _running = false;
    _paused = false;
    _lockCancel();
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
    _timer = Timer(Duration(microseconds: delayUs < 0 ? 0 : delayUs), _tick);
  }

  void _fireBeat(int beat) {
    if (!_muted) {
      final accent = _accents.contains(beat);
      final pl = accent ? _accent : _click;
      final src = accent ? _accentSrc : _clickSrc;
      // Replay the preloaded click from the start. play() restarts cleanly even
      // if the previous click is still ringing out.
      pl
          .play(src, volume: _volume)
          .catchError((e) => debugPrint('click error: $e'));
    }
    _beatController.add(beat);
    notifyListeners();
  }

  void setBpm(int value) {
    _bpm = value.clamp(20, 300);
    notifyListeners();
  }

  void nudgeBpm(int delta) => setBpm(_bpm + delta);

  void setTimeSignature(int numerator, int denominator) {
    _beatsPerBar = numerator.clamp(1, 16);
    _denominator = denominator;
    _accents = _computeAccents(_beatsPerBar, _denominator);
    if (_currentBeat >= _beatsPerBar) _currentBeat = 0;
    notifyListeners();
  }

  /// Compound meters (6/8, 9/8, 12/8) are felt in groups of three eighths, so
  /// accent the start of each group. Everything else accents just beat 1.
  static Set<int> _computeAccents(int numerator, int denominator) {
    if (denominator == 8 && numerator >= 6 && numerator % 3 == 0) {
      return {for (var i = 0; i < numerator; i += 3) i};
    }
    return {0};
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
    _savePrefs();
  }

  /// Shift the click relative to the music. Takes effect live while running, so
  /// the user can drag the slider and hear the click move into alignment.
  void setSyncOffset(int ms) {
    final clamped = ms.clamp(-1000, 1000);
    if (_locked) {
      // The poll reads the offset live, so boundaries shift smoothly as the
      // slider moves — no rescheduling needed.
      _syncOffsetMs = clamped;
      notifyListeners();
      return;
    }
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
    // In lock-mode the click follows the music position regardless of speed, so
    // nothing to reschedule. Free-mode re-locks to a clean downbeat.
    if (_running && !_paused && !_locked) {
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
    _lockTimer?.cancel();
    _beatController.close();
    _accent.dispose();
    _click.dispose();
    super.dispose();
  }
}
