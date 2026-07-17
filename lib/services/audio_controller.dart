import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';

/// Wraps a just_audio player for the practice music. Independent volume/mute
/// from the metronome so either source can be louder.
class AudioController extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  AudioPlayer get player => _player;

  List<Track> _queue = [];
  int _index = -1;
  int get index => _index;
  Track? get current =>
      (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;

  double _volume = 1.0;
  double get volume => _volume;
  bool _muted = false;
  bool get muted => _muted;

  double _speed = 1.0;
  double get speed => _speed;

  // Fires when the current track wraps back to the start (loop repeat), so the
  // metronome can re-lock to the downbeat and stay in sync.
  final _loopController = StreamController<void>.broadcast();
  Stream<void> get loopStream => _loopController.stream;
  Duration _lastPos = Duration.zero;

  AudioController() {
    _player.playerStateStream.listen((_) => notifyListeners());
    // Repeat the current track until the user explicitly moves to another one.
    _player.setLoopMode(LoopMode.one);
    // Detect the loop point: position jumps from near the end back to near 0.
    _player.positionStream.listen((pos) {
      final dur = _player.duration;
      if (dur != null && dur > const Duration(seconds: 1) && _player.playing) {
        const edge = Duration(milliseconds: 700);
        if (_lastPos > dur - edge && pos < edge) {
          _loopController.add(null);
        }
      }
      _lastPos = pos;
    });
  }

  bool get isPlaying => _player.playing;
  bool get hasNext => _index >= 0 && _index < _queue.length - 1;
  bool get hasPrev => _index > 0;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;

  Future<void> openQueue(List<Track> queue, int index) async {
    _queue = queue;
    // Load paused so the Play button can start music + metronome together.
    await _openIndex(index, autoplay: false);
  }

  Future<void> _openIndex(int index, {bool autoplay = false}) async {
    if (index < 0 || index >= _queue.length) return;
    _index = index;
    notifyListeners();
    try {
      await _player.setAudioSource(AudioSource.file(_queue[index].audioPath));
      await _applyVolume();
      await _player.setSpeed(_speed);
      if (autoplay) await _player.play();
    } catch (e) {
      debugPrint('Audio open error: $e');
    }
    notifyListeners();
  }

  Future<void> playPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> seek(Duration pos) => _player.seek(pos);

  Future<void> next() async {
    final wasPlaying = _player.playing;
    if (hasNext) await _openIndex(_index + 1, autoplay: wasPlaying);
  }

  Future<void> prev() async {
    // If we're more than 3s in, restart the current track instead.
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    final wasPlaying = _player.playing;
    if (hasPrev) await _openIndex(_index - 1, autoplay: wasPlaying);
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

  Future<void> _applyVolume() => _player.setVolume(_muted ? 0.0 : _volume);

  Future<void> setSpeed(double value) async {
    _speed = value <= 0 ? 1.0 : value;
    await _player.setSpeed(_speed);
    notifyListeners();
  }

  @override
  void dispose() {
    _loopController.close();
    _player.dispose();
    super.dispose();
  }
}
