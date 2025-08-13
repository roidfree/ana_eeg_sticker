// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:math' as math;
import 'eeg_models.dart';

/// Lightweight DSP: biquad filters and bandpower features in pure Dart.
/// We avoid FFT dependencies; band power ≈ RMS energy after bandpass.

class _Biquad {
  // Direct Form I
  double a0 = 1, a1 = 0, a2 = 0, b0 = 1, b1 = 0, b2 = 0;
  double x1 = 0, x2 = 0, y1 = 0, y2 = 0;

  double process(double x) {
    final y = (b0/a0)*x + (b1/a0)*x1 + (b2/a0)*x2 - (a1/a0)*y1 - (a2/a0)*y2;
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

  /// Bandpass (constant skirt gain). f0=center, Q ~ f0 / bandwidth.
  static _Biquad bandpass(double fs, double f0, double q) {
    final bq = _Biquad();
    final w0 = 2 * math.pi * f0 / fs;
    final cosw0 = math.cos(w0);
    final sinw0 = math.sin(w0);
    final alpha = sinw0 / (2 * q);

    bq.b0 =   sinw0/2;
    bq.b1 =   0;
    bq.b2 =  -sinw0/2;
    bq.a0 =   1 + alpha;
    bq.a1 =  -2 * cosw0;
    bq.a2 =   1 - alpha;
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
  return (n % 2 == 1) ? s[n ~/ 2] : 0.5 * (s[n ~/ 2 - 1] + s[n ~/ 2]);
}

double _meanSq(List<double> v) {
  if (v.isEmpty) return 0;
  double acc = 0;
  for (final x in v) { acc += x * x; }
  return acc / v.length;
}

class MinuteAnalyzer {
  MinuteAnalyzer({required this.fs, required this.channels});

  final int fs;
  final int channels;

  /// Analyze a 60s window and return per-minute scores & booleans.
  MinuteScores analyze(MinuteWindow w) {
    // Prepare: separate channel arrays, detrend by removing mean.
    final n = w.data.length;
    final x = List.generate(channels, (_) => List<double>.filled(n, 0));
    for (int i = 0; i < n; i++) {
      final vals = w.data[i].values;
      for (int c = 0; c < channels; c++) x[c][i] = vals[c].toDouble();
    }
    for (int c = 0; c < channels; c++) {
      final m = x[c].reduce((a, b) => a + b) / n;
      for (int i = 0; i < n; i++) x[c][i] -= m;
    }

    // Pre-filter: 1–45 Hz band-limiting + (optional) 50 Hz notch.
    final hp = _Biquad.highpass(fs.toDouble(), 1.0, 0.7071);
    final lp = _Biquad.lowpass(fs.toDouble(), 45.0, 0.7071);
    final notch50 = _Biquad.notch(fs.toDouble(), 50.0, 30.0); // Q=30 narrow
    for (int c = 0; c < channels; c++) {
      for (int i = 0; i < n; i++) {
        var y = hp.process(x[c][i]);
        y = lp.process(y);
        // If you're in 60 Hz mains region, comment this out and add 60 Hz notch.
        y = notch50.process(y);
        x[c][i] = y;
      }
    }

    // Bandpass filters per band. Q approximates f0 / bandwidth.
    List<double> bandRms(double f0, double bw) {
      final q = f0 / bw;
      final bp = _Biquad.bandpass(fs.toDouble(), f0, q);
      final out = <List<double>>[];
      for (int c = 0; c < channels; c++) {
        final yc = List<double>.filled(n, 0);
        for (int i = 0; i < n; i++) { yc[i] = bp.process(x[c][i]); }
        out.add(yc);
      }
      // RMS per channel
      return List<double>.generate(channels, (c) => math.sqrt(_meanSq(out[c])));
    }

    // Classic EEG bands (Hz): delta(1-4), theta(4-8), alpha(8-12), beta(12-30), gamma(30-45)
    final delta = bandRms(2.5, 3.0);
    final theta = bandRms(6.0, 4.0);
    final alpha = bandRms(10.0, 4.0);
    final beta  = bandRms(21.0, 18.0);
    final gamma = bandRms(37.5, 15.0);

    // Convert to relative powers per channel
    final relAlpha = <double>[];
    final relBeta  = <double>[];
    final relTheta = <double>[];
    for (int c = 0; c < channels; c++) {
      final tot = delta[c] + theta[c] + alpha[c] + beta[c] + gamma[c] + 1e-12;
      relAlpha.add(alpha[c] / tot);
      relBeta.add(beta[c]   / tot);
      relTheta.add(theta[c] / tot);
    }

    // Robust aggregates across channels
    final tbr = _median(List<double>.generate(channels, (i) => theta[i] / (beta[i] + 1e-12)));
    final alphaRelMed = _median(relAlpha);
    final betaRelMed  = _median(relBeta);

    // Map to scores (0..1)
    // Focus: lower TBR => higher focus. Threshold ~2.5; use sigmoid for smoothness.
    double sigmoid(double z) => 1.0 / (1.0 + math.exp(-z));
    final focusScore = sigmoid((2.5 - tbr) / 0.5).clamp(0.0, 1.0);

    // Stress: alpha suppression + beta elevation.
    // Target alpha_rel ~≥0.20 (calm), beta_rel ~≤0.25 (calm).
    final stressRaw = math.max(0, 0.25 - alphaRelMed) * 1.2 + math.max(0, betaRelMed - 0.25) * 1.0;
    final stressScore = stressRaw.clamp(0.0, 1.0);

    return MinuteScores(
      focusScore: focusScore,
      stressScore: stressScore,
      focused: focusScore > 0.5,
      stressed: stressScore > 0.5,
      windowEndMicros: w.windowEndMicros,
    );
  }
}
