import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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

  final FlutterAudioCapture _capture = FlutterAudioCapture();
  final PitchDetector _detector = PitchDetector(
    audioSampleRate: _sampleRate * 1.0,
    bufferSize: _bufferSize,
  );

  final List<double> _buf = [];
  bool _processing = false;
  bool _inited = false;

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
      _error = 'The tuner needs a microphone — open Metro Sound on your '
          'iPhone or iPad to tune.';
      notifyListeners();
      return;
    }
    try {
      if (!_inited) {
        await _capture.init();
        _inited = true;
      }
      await _capture.start(
        _onData,
        (Object e) {
          _error = '$e';
          notifyListeners();
        },
        sampleRate: _sampleRate,
        bufferSize: _bufferSize,
      );
      _error = null;
      _listening = true;
      notifyListeners();
    } catch (e) {
      _error = '$e';
      debugPrint('Tuner start error: $e');
      notifyListeners();
    }
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
