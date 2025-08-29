// lib/services/eeg_recorder.dart
// ignore_for_file: unused_local_variable, unintended_html_in_doc_comment

import 'dart:async';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

/// Buffers a 4-channel EEG stream (List<double> length 4) and saves a CSV
/// every 60 seconds based on timestamps. Robust to any sampling rate.
class EEGRecorder {
  EEGRecorder({required this.eegStream, Duration chunkLength = const Duration(seconds: 60)})
      : _chunkLen = chunkLength;

  final Stream<List<double>> eegStream;

  StreamSubscription<List<double>>? _sub;
  final List<_Row> _rows = [];

  DateTime? _chunkStart;
  final Duration _chunkLen;

  final _savedFilesController = StreamController<File>.broadcast();
  Stream<File> get savedFiles => _savedFilesController.stream;

  bool _flushing = false;
  bool get isRecording => _sub != null;

  /// Start buffering the incoming samples. Each time 60s elapse since the first
  /// sample of a chunk, a CSV is written and emitted on [savedFiles].
  Future<void> start() async {
    if (_sub != null) return;

    _sub = eegStream.listen((sample) async {
      if (sample.length != 4) return;

      final now = DateTime.now().toUtc();
      _rows.add(_Row(now, sample[0], sample[1], sample[2], sample[3]));
      _chunkStart ??= now;

      // If we've reached the chunk length, flush to CSV.
      if (!_flushing && now.difference(_chunkStart!).abs() >= _chunkLen) {
        _flushing = true;
        try {
          final file = await _flushToCsv(_rows);
          _rows.clear();
          _chunkStart = null;
          _savedFilesController.add(file);
        } finally {
          _flushing = false;
        }
      }
    });
  }

  /// Stop recording and flush any remaining partial chunk to a CSV.
  Future<File?> stop() async {
    await _sub?.cancel();
    _sub = null;

    if (_rows.isEmpty) return null;

    _flushing = true;
    try {
      final file = await _flushToCsv(_rows);
      _rows.clear();
      _chunkStart = null;
      _savedFilesController.add(file);
      return file;
    } finally {
      _flushing = false;
    }
  }

  Future<File> _flushToCsv(List<_Row> rows) async {
    final dir = await getApplicationDocumentsDirectory();
    final start = rows.first.t;
    final end = rows.last.t;

    final stamp = DateFormat("yyyyMMdd_HHmmss").format(start);
    final path = "${dir.path}/eeg_${stamp}_${rows.length}samples.csv";
    final file = File(path);

    final sb = StringBuffer()
      ..writeln("timestamp_utc,ch1,ch2,ch3,ch4");
    for (final r in rows) {
      sb.writeln("${r.t.toIso8601String()},${r.c1},${r.c2},${r.c3},${r.c4}");
    }
    await file.writeAsString(sb.toString(), flush: true);
    return file;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _savedFilesController.close();
  }
}

class _Row {
  _Row(this.t, this.c1, this.c2, this.c3, this.c4);
  final DateTime t;
  final double c1, c2, c3, c4;
}
