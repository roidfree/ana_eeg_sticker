// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';
import 'eeg_models.dart';

/// Accumulates multi-channel EEG samples and emits a 60s window when full.
/// You feed channel messages (Channel 1..4) as they arrive; it assembles
/// complete sample frames (all channels present) before counting.
class EegMinuteBuffer {
  EegMinuteBuffer({
    required this.channels,
    required this.samplingHz,
    this.windowSeconds = 60,
  }) : _neededPerMinute = samplingHz * windowSeconds {
    init();
  }

  final int channels;
  final int samplingHz;
  final int windowSeconds;
  final int _neededPerMinute;

  final List<int?> _currentFrame = [];
  int _frameMask = 0;

  final List<EegSample> _buffer = [];
  int? _windowStartMicros;

  final _minuteController = StreamController<MinuteWindow>.broadcast();
  Stream<MinuteWindow> get minuteStream => _minuteController.stream;

  void init() {
    _currentFrame
      ..clear()
      ..addAll(List<int?>.filled(channels, null));
    _frameMask = 0;
    _buffer.clear();
    _windowStartMicros = null;
  }

  /// Call this when a single *channel* value arrives (1-based channel index).
  void addChannelValue({required int channelIndex1, required int value}) {
    final nowMicros = DateTime.now().microsecondsSinceEpoch;
    _windowStartMicros ??= nowMicros;

    final idx = channelIndex1 - 1;
    if (idx < 0 || idx >= channels) return;

    _currentFrame[idx] = value;
    _frameMask |= (1 << idx);

    if (_frameMask == ((1 << channels) - 1)) {
      // We have all channels for this tick — commit a sample.
      final values = List<int>.generate(channels, (i) => _currentFrame[i] ?? 0);
      _buffer.add(EegSample(nowMicros, values));

      // Reset frame for next tick
      for (int i = 0; i < channels; i++) _currentFrame[i] = null;
      _frameMask = 0;

      // Minute full?
      if (_buffer.length >= _neededPerMinute) {
        _flushMinute();
      }
    }
  }

  void _flushMinute() {
    final windowEnd = _buffer.isNotEmpty ? _buffer.last.tMicros : (_windowStartMicros ?? 0);
    final minute = MinuteWindow(
      samplingHz: samplingHz,
      channels: channels,
      data: List<EegSample>.from(_buffer),
      windowStartMicros: _windowStartMicros ?? windowEnd,
      windowEndMicros: windowEnd,
    );

    _minuteController.add(minute);

    // Reset for next minute
    _buffer.clear();
    _windowStartMicros = null;
  }

  Future<void> dispose() async {
    await _minuteController.close();
  }
}
