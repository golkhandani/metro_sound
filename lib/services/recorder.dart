import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_audio_capture/flutter_audio_capture.dart';

enum RecState { idle, recording, paused, stopped }

/// Records the microphone to in-memory 16-bit PCM using flutter_audio_capture
/// (same plugin as the tuner — no new dependency). Supports pause/resume, a
/// live input level, a waveform for trimming, and a selectable sample rate.
/// Needs a real mic — iOS/Android only, not macOS desktop.
class Recorder extends ChangeNotifier {
  static const _micChannel = MethodChannel('metro_sound/mic');

  final FlutterAudioCapture _capture = FlutterAudioCapture();
  bool _inited = false;

  RecState _state = RecState.idle;
  String? _error;
  int _sampleRate = 44100; // 44100 = High, 22050 = Voice

  // Captured little-endian 16-bit PCM and a snapshot taken on stop().
  final BytesBuilder _pcm = BytesBuilder();
  int _sampleCount = 0;
  Uint8List _recorded = Uint8List(0);

  double _level = 0; // live input level 0..1 (peak, with decay)

  RecState get state => _state;
  String? get error => _error;
  int get sampleRate => _sampleRate;
  double get level => _level;
  bool get isRecording => _state == RecState.recording;
  bool get isPaused => _state == RecState.paused;
  bool get hasTake => _state == RecState.stopped && _recorded.isNotEmpty;

  static bool get supported =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid || Platform.isLinux);

  Duration get elapsed =>
      Duration(milliseconds: (_sampleCount * 1000 / _sampleRate).round());

  void setSampleRate(int rate) {
    if (_state != RecState.idle) return; // can't change mid-take
    _sampleRate = rate;
    notifyListeners();
  }

  Future<bool> _ensureMicPermission() async {
    if (!Platform.isIOS) return true;
    try {
      final granted = await _micChannel.invokeMethod<bool>('requestPermission');
      return granted ?? false;
    } catch (_) {
      return true; // channel missing (older build) — let capture try anyway
    }
  }

  /// Begin a fresh take.
  Future<bool> start() async {
    if (_state == RecState.recording) return true;
    if (!supported) {
      _error = 'Recording needs a microphone — use Metro Sound on your iPhone.';
      notifyListeners();
      return false;
    }
    if (!await _ensureMicPermission()) {
      _error = 'Microphone access is off. Enable it in Settings → Metro Sound.';
      notifyListeners();
      return false;
    }
    _pcm.clear();
    _sampleCount = 0;
    _recorded = Uint8List(0);
    return _beginCapture();
  }

  Future<bool> resume() async {
    if (_state != RecState.paused) return false;
    return _beginCapture();
  }

  Future<bool> _beginCapture() async {
    try {
      if (!_inited) {
        await _capture.init();
        _inited = true;
      }
      _error = null;
      await _capture.start(
        _onData,
        (Object e) {
          _error = '$e';
          notifyListeners();
        },
        sampleRate: _sampleRate,
        bufferSize: 3000,
      );
      _state = RecState.recording;
      notifyListeners();
      return true;
    } catch (e) {
      _error = '$e';
      debugPrint('Recorder start error: $e');
      notifyListeners();
      return false;
    }
  }

  Future<void> pause() async {
    if (_state != RecState.recording) return;
    try {
      await _capture.stop();
    } catch (_) {}
    _level = 0;
    _state = RecState.paused;
    notifyListeners();
  }

  /// Finish the take and keep it for review/trim.
  Future<void> stop() async {
    if (_state != RecState.recording && _state != RecState.paused) return;
    if (_state == RecState.recording) {
      try {
        await _capture.stop();
      } catch (_) {}
    }
    _recorded = _pcm.toBytes();
    _level = 0;
    _state = RecState.stopped;
    notifyListeners();
  }

  /// Discard everything and go back to idle.
  Future<void> reset() async {
    if (_state == RecState.recording) {
      try {
        await _capture.stop();
      } catch (_) {}
    }
    _pcm.clear();
    _sampleCount = 0;
    _recorded = Uint8List(0);
    _level = 0;
    _error = null;
    _state = RecState.idle;
    notifyListeners();
  }

  void _onData(dynamic obj) {
    final samples = obj as Float32List;
    final bytes = Uint8List(samples.length * 2);
    final view = ByteData.view(bytes.buffer);
    var peak = 0.0;
    for (var i = 0; i < samples.length; i++) {
      final a = samples[i].abs();
      if (a > peak) peak = a;
      final v = (samples[i] * 32767).clamp(-32768, 32767).toInt();
      view.setInt16(i * 2, v, Endian.little);
    }
    _pcm.add(bytes);
    _sampleCount += samples.length;
    // Peak meter with a gentle fall so it reads smoothly.
    _level = math.max(peak.clamp(0.0, 1.0), _level * 0.82);
    notifyListeners();
  }

  /// Downsampled amplitude envelope (0..1) of the captured take for drawing.
  List<double> waveform(int buckets) {
    final total = _recorded.length ~/ 2;
    if (total == 0 || buckets <= 0) return List.filled(buckets, 0);
    final view = ByteData.view(_recorded.buffer);
    final per = (total / buckets).ceil();
    final out = List<double>.filled(buckets, 0);
    for (var b = 0; b < buckets; b++) {
      var peak = 0;
      final from = b * per;
      for (var i = from; i < from + per && i < total; i++) {
        final s = view.getInt16(i * 2, Endian.little).abs();
        if (s > peak) peak = s;
      }
      out[b] = peak / 32768;
    }
    return out;
  }

  Duration get takeDuration =>
      Duration(milliseconds: (_recorded.length ~/ 2) * 1000 ~/ _sampleRate);

  /// Export the take (optionally trimmed to [startFrac]..[endFrac]) as WAV.
  Uint8List exportWav({double startFrac = 0, double endFrac = 1}) {
    final total = _recorded.length ~/ 2;
    var s = (startFrac.clamp(0.0, 1.0) * total).floor();
    var e = (endFrac.clamp(0.0, 1.0) * total).ceil();
    if (e <= s) e = total;
    final slice = _recorded.sublist(s * 2, e * 2);
    return _wav(slice, _sampleRate);
  }

  static Uint8List _wav(Uint8List pcm, int sampleRate) {
    final out = BytesBuilder();
    void str(String x) => out.add(x.codeUnits);
    void u32(int v) => out
        .add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
    void u16(int v) => out
        .add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());

    final dataLen = pcm.length;
    str('RIFF');
    u32(36 + dataLen);
    str('WAVE');
    str('fmt ');
    u32(16);
    u16(1); // PCM
    u16(1); // mono
    u32(sampleRate);
    u32(sampleRate * 2);
    u16(2);
    u16(16);
    str('data');
    u32(dataLen);
    out.add(pcm);
    return out.toBytes();
  }

  @override
  void dispose() {
    if (_state == RecState.recording) {
      try {
        _capture.stop();
      } catch (_) {}
    }
    super.dispose();
  }
}
