// lib/services/eeg_recorder.dart
// ignore_for_file: unintended_html_in_doc_comment, unused_local_variable

import 'dart:async';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

/// Buffers a 4-channel EEG stream (List<double> of length 4)
/// and saves a CSV every minute (1560 samples at 26 Hz).
class EEGRecorder {
  EEGRecorder({
    required this.eegStream,
    this.fs = 256.0,
  });

  final Stream<List<double>> eegStream;
  final double fs;

  StreamSubscription<List<double>>? _sub;
  final List<_Row> _buffer = [];
  int _samplesPerMinute = 0;

  final _savedFilesController = StreamController<File>.broadcast();
  Stream<File> get savedFiles => _savedFilesController.stream;

  bool get isRecording => _sub != null;

  Future<void> start() async {
    if (_sub != null) return;
    _samplesPerMinute = (60 * fs).round(); // 1560 at 26 Hz

    _sub = eegStream.listen((ch) async {
      if (ch.length != 4) return;
      _buffer.add(_Row(DateTime.now().toUtc(), ch[0], ch[1], ch[2], ch[3]));

      if (_buffer.length >= _samplesPerMinute) {
        final f = await _flushToCsv(_buffer);
        _buffer.clear();
        _savedFilesController.add(f);
      }
    });
  }

  /// Stops and flushes (if anything remains) to a final CSV.
  Future<File?> stop() async {
    await _sub?.cancel();
    _sub = null;
    if (_buffer.isEmpty) return null;
    final f = await _flushToCsv(_buffer);
    _buffer.clear();
    _savedFilesController.add(f);
    return f;
  }

  Future<File> _flushToCsv(List<_Row> rows) async {
    final dir = await getApplicationDocumentsDirectory();
    final start = rows.first.t;
    final end = rows.last.t;
    final stamp = DateFormat("yyyyMMdd_HHmmss").format(start);
    final file = File("${dir.path}/eeg_${stamp}_${rows.length}samples.csv");

    final sb = StringBuffer();
    // header
    sb.writeln("timestamp_utc,ch1,ch2,ch3,ch4");
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
