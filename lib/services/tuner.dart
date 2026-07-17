import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_audio_capture/flutter_audio_capture.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';

/// Chromatic instrument tuner: streams the mic, runs YIN pitch detection, and
/// maps the frequency to the nearest note + cents deviation.
///
/// Uses flutter_audio_capture (iOS/Android/Linux). macOS has no mic plugin, so
/// the tuner reports it's available on a phone instead.
class Tuner extends ChangeNotifier {
  static const int _sampleRate = 44100;
  static const int _bufferSize = 2048;

  // Recreated on every start(): the plugin's init() is once-per-instance, and
  // it's the ONLY call that puts the AVAudioSession back into a record-capable
  // category. Leaving the tab restores a playback session (for normal volume),
  // so a stale instance skips setup and the mic engine reports a dead 0 Hz
  // input ("Invalid sample rate"). A fresh instance re-runs the native setup.
  FlutterAudioCapture _capture = FlutterAudioCapture();
  final PitchDetector _detector = PitchDetector(
    audioSampleRate: _sampleRate.toDouble(),
    bufferSize: _bufferSize,
  );

  final List<double> _buf = [];
  bool _processing = false;
  bool _wasInTune = false;

  // 12 = semitones, 24 = Persian quarter-tones (set from settings).
  int _divisions = 12;
  void setDivisions(int d) => _divisions = d;

  bool get supported =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid || Platform.isLinux);

  bool _listening = false;
  bool get listening => _listening;

  // _pitched = a live signal *this frame*. _hasReading = we have a last value to
  // display (held on screen even after the note decays to silence).
  bool _pitched = false;
  bool get pitched => _pitched;
  bool get live => _pitched;

  bool _hasReading = false;
  bool get hasReading => _hasReading;

  double _frequency = 0;
  double get frequency => _frequency;

  // Chromatic pitch class 0–11 (−1 when nothing detected). The UI maps this to
  // a name via the chosen naming system (letters or solfège).
  int _noteIndex = -1;
  int get noteIndex => _noteIndex;

  int _octave = 0;
  int get octave => _octave;

  int _cents = 0;
  int get cents => _cents;

  double _needle = 0;
  double get needle => _needle;

  bool get inTune => _hasReading && _cents.abs() <= 5;

  String? _error;
  String? get error => _error;

  Future<void> start() async {
    if (_listening) return;
    if (!supported) {
      _error =
          'The tuner needs a microphone — open Metro Sound on your '
          'iPhone or iPad to tune.';
      notifyListeners();
      return;
    }
    // A fresh plugin instance per attempt: init() runs once per instance and
    // is what re-establishes the record session (leaving the tab restores the
    // playback session for normal volume, which kills mic input). Failures can
    // arrive via the ERROR CALLBACK rather than a thrown exception, so each
    // attempt watches the callback during a short probation window.
    Object? lastError;
    Future<bool> attempt() async {
      Object? callbackError;
      var probing = true;
      try {
        // Release any half-started engine from a previous attempt, then
        // rebuild so init() truly re-runs the native session setup.
        try {
          await _capture.stop();
        } catch (_) {}
        _capture = FlutterAudioCapture();
        final inited = await _capture.init();
        if (inited != true) {
          lastError = 'audio session init failed';
          return false;
        }
        await _capture.start(
          _onData,
          (Object e) {
            if (probing) {
              // Swallow during the probe — a retried start isn't user-facing.
              callbackError ??= e;
            } else {
              _error = '$e';
              notifyListeners();
            }
          },
          sampleRate: _sampleRate,
          bufferSize: _bufferSize,
        );
      } catch (e) {
        debugPrint('Tuner start threw: $e');
        lastError = e;
        return false;
      }
      // Probation: give the engine a beat to report an async failure.
      await Future.delayed(const Duration(milliseconds: 300));
      probing = false;
      if (callbackError != null) {
        debugPrint('Tuner start failed via callback: $callbackError');
        lastError = callbackError;
        return false;
      }
      return true;
    }

    var ok = false;
    for (var tries = 0; tries < 2 && !ok; tries++) {
      ok = await attempt();
    }
    if (ok) {
      _error = null;
      _listening = true;
    } else {
      _error = 'Couldn\'t start the microphone'
          '${lastError != null ? ' ($lastError)' : ''}. '
          'Leave and re-open the Tuner tab to try again.';
    }
    notifyListeners();
  }

  Future<void> stop() async {
    if (!_listening) return;
    _listening = false;
    try {
      await _capture.stop();
    } catch (_) {}
    _buf.clear();
    _pitched = false;
    _hasReading = false;
    _noteIndex = -1;
    _needle = 0;
    notifyListeners();
  }

  void _onData(dynamic obj) {
    final samples = obj as Float32List;
    _buf.addAll(samples);
    if (_buf.length > _bufferSize * 4) {
      _buf.removeRange(0, _buf.length - _bufferSize * 2);
    }
    if (_processing || _buf.length < _bufferSize) return;
    _processing = true;
    final window = _buf.sublist(0, _bufferSize);
    _buf.removeRange(0, _bufferSize);
    _analyze(window);
  }

  Future<void> _analyze(List<double> window) async {
    try {
      final result = await _detector.getPitchFromFloatBuffer(window);
      final f = result.pitch;
      final ok =
          result.pitched && result.probability > 0.72 && f > 40 && f < 2000;
      if (ok) {
        _frequency = f;
        final divs = _divisions;
        final centsPerDiv = 1200 / divs;
        // Continuous step index in the chosen division system (A4 = 440Hz).
        final stepF = (69 + 12 * (math.log(f / 440) / math.ln2)) * (divs / 12);
        final nearest = stepF.round();
        _cents = ((stepF - nearest) * centsPerDiv).round();
        _noteIndex = nearest % divs;
        _octave = (nearest ~/ divs) - 1;
        // Light haptic the moment the note locks into tune.
        final nowInTune = _cents.abs() <= 5;
        if (nowInTune && !_wasInTune) HapticFeedback.lightImpact();
        _wasInTune = nowInTune;
        _pitched = true;
        _hasReading = true;
        _needle += (_cents - _needle) * 0.35;
      } else {
        // Note decayed to silence: stop being "live" but HOLD the last reading
        // (note, cents, needle) on screen so it can be read.
        _pitched = false;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Tuner analyze error: $e');
    } finally {
      _processing = false;
    }
  }

  @override
  void dispose() {
    if (_listening) _capture.stop();
    super.dispose();
  }
}
