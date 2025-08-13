// lib/services/ble_service.dart
//
// BLE + EEG minute analyzer (pure Dart), keeping your scanning/connecting/streaming.
//
// - Scans & connects to Nordic UART Service (NUS).
// - Subscribes to TX notifications, parses 4× int16 (LE) per packet.
// - Emits raw 4-ch samples via eegStream.
// - Buffers ~60s of samples, analyzes on-device, and exposes:
//     focused$, stressed$, focusScore$, stressScore$,
//     focusSeriesStream, stressSeriesStream.
//
// NOTE: Call connectDevice(...) after picking a device from scan(),
//       and call disconnect() on teardown.

// ignore_for_file: avoid_print, deprecated_member_use, curly_braces_in_flow_control_structures

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// ---------- Top-level helpers (must NOT be inside a class) ----------

/// Simple Direct-Form I biquad filter.
class _Biquad {
  double a0 = 1, a1 = 0, a2 = 0, b0 = 1, b1 = 0, b2 = 0;
  double x1 = 0, x2 = 0, y1 = 0, y2 = 0;

  double process(double x) {
    final y = (b0 / a0) * x + (b1 / a0) * x1 + (b2 / a0) * x2 - (a1 / a0) * y1 - (a2 / a0) * y2;
    x2 = x1; x1 = x;
    y2 = y1; y1 = y;
    return y;
  }

  static _Biquad lowpass(double fs, double fc, double q) {
    final bq = _Biquad();
    final w0 = 2 * math.pi * fc / fs;
    final cosw0 = math.cos(w0);
    final sinw0 = math.sin(w0);
    final alpha = sinw0 / (2 * q);
    bq.b0 = (1 - cosw0) / 2;
    bq.b1 = 1 - cosw0;
    bq.b2 = (1 - cosw0) / 2;
    bq.a0 = 1 + alpha;
    bq.a1 = -2 * cosw0;
    bq.a2 = 1 - alpha;
    return bq;
  }

  static _Biquad highpass(double fs, double fc, double q) {
    final bq = _Biquad();
    final w0 = 2 * math.pi * fc / fs;
    final cosw0 = math.cos(w0);
    final sinw0 = math.sin(w0);
    final alpha = sinw0 / (2 * q);
    bq.b0 = (1 + cosw0) / 2;
    bq.b1 = -(1 + cosw0);
    bq.b2 = (1 + cosw0) / 2;
    bq.a0 = 1 + alpha;
    bq.a1 = -2 * cosw0;
    bq.a2 = 1 - alpha;
    return bq;
  }

  /// Bandpass at center f0 with bandwidth ~ f0 / Q.
  static _Biquad bandpass(double fs, double f0, double q) {
    final bq = _Biquad();
    final w0 = 2 * math.pi * f0 / fs;
    final cosw0 = math.cos(w0);
    final sinw0 = math.sin(w0);
    final alpha = sinw0 / (2 * q);
    bq.b0 =  sinw0 / 2;
    bq.b1 =  0;
    bq.b2 = -sinw0 / 2;
    bq.a0 =  1 + alpha;
    bq.a1 = -2 * cosw0;
    bq.a2 =  1 - alpha;
    return bq;
  }

  static _Biquad notch(double fs, double f0, double q) {
    final bq = _Biquad();
    final w0 = 2 * math.pi * f0 / fs;
    final cosw0 = math.cos(w0);
    final sinw0 = math.sin(w0);
    final alpha = sinw0 / (2 * q);
    bq.b0 = 1;
    bq.b1 = -2 * cosw0;
    bq.b2 = 1;
    bq.a0 = 1 + alpha;
    bq.a1 = -2 * cosw0;
    bq.a2 = 1 - alpha;
    return bq;
  }
}

double _median(List<double> v) {
  if (v.isEmpty) return 0;
  final s = List<double>.from(v)..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : 0.5 * (s[n ~/ 2 - 1] + s[n ~/ 2]);
}

double _meanSq(List<double> v) {
  if (v.isEmpty) return 0;
  double acc = 0;
  for (final x in v) acc += x * x;
  return acc / v.length;
}

class _MinuteScores {
  _MinuteScores(this.focusScore, this.stressScore, this.focused, this.stressed);
  final double focusScore;  // 0..1 (1 = focused)
  final double stressScore; // 0..1 (1 = stressed)
  final bool focused;
  final bool stressed;
}

/// --------------------------------------------------------------------

class BLEService {
  // ---------- BLE (scan/connect/stream) ----------
  BluetoothDevice? _device;
  late BluetoothCharacteristic _txChar; // notify
  late BluetoothCharacteristic _rxChar; // write

  final _eegController = StreamController<List<double>>.broadcast();
  Stream<List<double>> get eegStream => _eegController.stream;

  // Nordic UART UUIDs
  static final Guid _svcUuid = Guid("6e400001-b5a3-f393-e0a9-e50e24dcca9e");
  static final Guid _txUuid  = Guid("6e400003-b5a3-f393-e0a9-e50e24dcca9e");
  static final Guid _rxUuid  = Guid("6e400002-b5a3-f393-e0a9-e50e24dcca9e");

  // ---------- Analyzer state ----------
  static const int _channels = 4;
  static const int _minFs = 20;
  static const int _maxFs = 512;

  final List<List<double>> _minuteBuf = <List<double>>[];
  int? _minuteStartMicros;
  int _sampleCountThisMinute = 0;

  final _focusedCtrl      = StreamController<bool>.broadcast();
  final _stressedCtrl     = StreamController<bool>.broadcast();
  final _focusScoreCtrl   = StreamController<double>.broadcast();
  final _stressScoreCtrl  = StreamController<double>.broadcast();

  bool _focused = false;
  bool _stressed = false;
  double _focusScore = 0.0;
  double _stressScore = 0.0;

  Stream<bool>   get focused$      => _focusedCtrl.stream;
  Stream<bool>   get stressed$     => _stressedCtrl.stream;
  Stream<double> get focusScore$   => _focusScoreCtrl.stream;
  Stream<double> get stressScore$  => _stressScoreCtrl.stream;

  static const int _maxMinutesHistory = 60;
  final List<double> _focusSeries  = <double>[];
  final List<double> _stressSeries = <double>[];

  final _focusSeriesCtrl  = StreamController<List<double>>.broadcast();
  final _stressSeriesCtrl = StreamController<List<double>>.broadcast();
  Stream<List<double>> get focusSeriesStream  => _focusSeriesCtrl.stream;
  Stream<List<double>> get stressSeriesStream => _stressSeriesCtrl.stream;

  // ----------------- Scanning -----------------
  Future<List<ScanResult>> scan({Duration timeout = const Duration(seconds: 5)}) async {
    final Map<String, ScanResult> results = {};
    await FlutterBluePlus.startScan(timeout: timeout);
    final sub = FlutterBluePlus.scanResults.listen((rList) {
      for (final r in rList) {
        results[r.device.id.id] = r;
      }
    });
    await Future.delayed(timeout);
    await FlutterBluePlus.stopScan();
    await sub.cancel();
    return results.values.toList();
  }

  // --------------- Connect & subscribe ---------------
  Future<bool> connectDevice(BluetoothDevice device) async {
    try {
      await device.connect(autoConnect: false);
      _device = device;

      final svcs = await device.discoverServices();
      final uartService = svcs.firstWhere((s) => s.uuid == _svcUuid);

      _txChar = uartService.characteristics.firstWhere((c) => c.uuid == _txUuid);
      _rxChar = uartService.characteristics.firstWhere((c) => c.uuid == _rxUuid);

      await _txChar.setNotifyValue(true);
      _txChar.value.listen(_handleData);

      // start streaming
      await _rxChar.write([0x01], withoutResponse: false);

      _resetMinute();
      return true;
    } catch (e) {
      print('BLE connectDevice error: $e');
      return false;
    }
  }

  // --------------- Notification handler ---------------
  void _handleData(List<int> raw) {
    if (raw.length < 8) return;

    final bd = ByteData.sublistView(Uint8List.fromList(raw));
    final sample = List<double>.generate(4, (i) {
      return bd.getInt16(i * 2, Endian.little).toDouble();
    });

    // Emit raw stream for existing UI
    _eegController.add(sample);

    // Feed minute analyzer
    _addSampleForMinute(sample);
  }

  // --------------- Disconnect / cleanup ---------------
  Future<void> disconnect() async {
    try { await _txChar.setNotifyValue(false); } catch (_) {}
    try { await _rxChar.write([0x00], withoutResponse: false); } catch (_) {}
    try { await _device?.disconnect(); } catch (_) {}

    await _eegController.close();

    await _focusedCtrl.close();
    await _stressedCtrl.close();
    await _focusScoreCtrl.close();
    await _stressScoreCtrl.close();
    await _focusSeriesCtrl.close();
    await _stressSeriesCtrl.close();
  }

  // ============================================================
  // =============== Minute Buffer + Dart Analyzer ==============
  // ============================================================
  void _resetMinute() {
    _minuteBuf.clear();
    _minuteStartMicros = null;
    _sampleCountThisMinute = 0;
  }

  void _addSampleForMinute(List<double> sample) {
    final nowMicros = DateTime.now().microsecondsSinceEpoch;
    _minuteStartMicros ??= nowMicros;

    _minuteBuf.add(sample);
    _sampleCountThisMinute++;

    final elapsedMicros = nowMicros - (_minuteStartMicros ?? nowMicros);
    if (elapsedMicros >= 60 * 1000000) {
      _flushAnalyzeMinute(nowMicros);
    }
  }

  void _flushAnalyzeMinute(int endMicros) {
    if (_minuteBuf.isEmpty || _minuteStartMicros == null) {
      _resetMinute();
      return;
    }

    final startMicros = _minuteStartMicros!;
    final elapsedSec = (endMicros - startMicros) / 1e6;
    int fsEst = elapsedSec > 0 ? (_sampleCountThisMinute / elapsedSec).round() : 0;
    fsEst = fsEst.clamp(_minFs, _maxFs);

    final scores = _analyzeWindow(
      samples: _minuteBuf,
      fs: fsEst,
      channels: _channels,
    );

    _focused = scores.focused;
    _stressed = scores.stressed;
    _focusScore = scores.focusScore;
    _stressScore = scores.stressScore;

    _focusedCtrl.add(_focused);
    _stressedCtrl.add(_stressed);
    _focusScoreCtrl.add(_focusScore);
    _stressScoreCtrl.add(_stressScore);

    _focusSeries.add(_focusScore);
    _stressSeries.add(_stressScore);
    if (_focusSeries.length > _maxMinutesHistory) _focusSeries.removeAt(0);
    if (_stressSeries.length > _maxMinutesHistory) _stressSeries.removeAt(0);
    _focusSeriesCtrl.add(List<double>.from(_focusSeries));
    _stressSeriesCtrl.add(List<double>.from(_stressSeries));

    _resetMinute();
  }

  // ---------------- Core analysis (pure Dart) ----------------
  _MinuteScores _analyzeWindow({
    required List<List<double>> samples,
    required int fs,
    required int channels,
  }) {
    final n = samples.length;
    if (n == 0) return _MinuteScores(0, 0, false, false);

    // Arrange [channels × n] & detrend
    final x = List.generate(channels, (_) => List<double>.filled(n, 0));
    for (int i = 0; i < n; i++) {
      final row = samples[i];
      for (int c = 0; c < channels; c++) x[c][i] = row[c];
    }
    for (int c = 0; c < channels; c++) {
      final m = x[c].reduce((a, b) => a + b) / n;
      for (int i = 0; i < n; i++) x[c][i] -= m;
    }

    // Band-limit 1–45 Hz + 50 Hz notch (per-channel filter states)
    for (int c = 0; c < channels; c++) {
      final hp = _Biquad.highpass(fs.toDouble(), 1.0, 0.7071);
      final lp = _Biquad.lowpass(fs.toDouble(), 45.0, 0.7071);
      final notch50 = _Biquad.notch(fs.toDouble(), 50.0, 30.0);
      for (int i = 0; i < n; i++) {
        var y = hp.process(x[c][i]);
        y = lp.process(y);
        y = notch50.process(y); // swap to 60 Hz if needed
        x[c][i] = y;
      }
    }

    List<double> bandRms(double f0, double bw) {
      final q = f0 / bw;
      final out = <double>[];
      for (int c = 0; c < channels; c++) {
        final bp = _Biquad.bandpass(fs.toDouble(), f0, q);
        final yc = List<double>.filled(n, 0);
        for (int i = 0; i < n; i++) {
          yc[i] = bp.process(x[c][i]);
        }
        out.add(math.sqrt(_meanSq(yc)));
      }
      return out;
    }

    // EEG bands
    final delta = bandRms(2.5, 3.0);   // 1–4
    final theta = bandRms(6.0, 4.0);   // 4–8
    final alpha = bandRms(10.0, 4.0);  // 8–12
    final beta  = bandRms(21.0, 18.0); // 12–30
    final gamma = bandRms(37.5, 15.0); // 30–45

    // Relative powers
    final relAlpha = <double>[];
    final relBeta  = <double>[];
    for (int c = 0; c < channels; c++) {
      final tot = delta[c] + theta[c] + alpha[c] + beta[c] + gamma[c] + 1e-12;
      relAlpha.add(alpha[c] / tot);
      relBeta.add(beta[c] / tot);
    }

    // Focus via TBR
    final tbr = _median(List<double>.generate(channels, (i) => theta[i] / (beta[i] + 1e-12)));
    double sigmoid(double z) => 1.0 / (1.0 + math.exp(-z));
    final focusScore = sigmoid((2.5 - tbr) / 0.5).clamp(0.0, 1.0);

    // Stress via α suppression + β elevation
    final alphaRelMed = _median(relAlpha);
    final betaRelMed  = _median(relBeta);
    final stressRaw = math.max(0, 0.25 - alphaRelMed) * 1.2 + math.max(0, betaRelMed - 0.25) * 1.0;
    final stressScore = stressRaw.clamp(0.0, 1.0);

    final focused = focusScore > 0.5;
    final stressed = stressScore > 0.5;

    return _MinuteScores(focusScore, stressScore, focused, stressed);
  }
}
