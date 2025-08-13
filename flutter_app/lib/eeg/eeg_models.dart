class EegSample {
  EegSample(this.tMicros, this.values);
  final int tMicros;       // Monotonic timestamp (microseconds)
  final List<int> values;  // Raw counts per channel (length = channels)
}

class MinuteWindow {
  MinuteWindow({
    required this.samplingHz,
    required this.channels,
    required this.data, // samples in time order
    required this.windowStartMicros,
    required this.windowEndMicros,
  });

  final int samplingHz;
  final int channels;
  final List<EegSample> data;
  final int windowStartMicros;
  final int windowEndMicros;
}

class MinuteScores {
  MinuteScores({
    required this.focusScore,  // 0..1 (1 = focused)
    required this.stressScore, // 0..1 (1 = stressed)
    required this.focused,     // focusScore > 0.5 ?
    required this.stressed,    // stressScore > 0.5 ?
    required this.windowEndMicros,
  });

  final double focusScore;
  final double stressScore;
  final bool focused;
  final bool stressed;
  final int windowEndMicros;
}


