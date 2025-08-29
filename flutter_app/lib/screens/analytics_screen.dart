import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AnalyticsScreen extends StatefulWidget {
  final Stream<List<double>> eegStream;
  final Stream<List<double>> focusSeriesStream;
  final Stream<List<double>> stressSeriesStream;

  const AnalyticsScreen({
    required this.eegStream,
    required this.focusSeriesStream,
    required this.stressSeriesStream,
    super.key,
  });

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with AutomaticKeepAliveClientMixin {
  static const int _maxPoints = 256;
  final List<List<FlSpot>> _channels = List.generate(4, (_) => []);
  late StreamSubscription<List<double>> _sub;
  Timer? _uiTimer;

  // Minute tick aligned to wall clock
  Timer? _minuteTickTimer;

  List<double> _focusScores = [];
  List<DateTime> _focusTimestamps = [];
  List<double> _stressScores = [];
  List<DateTime> _stressTimestamps = [];
  List<String> _minuteLabels = [];

  DateTime? _focusFilterStart;
  DateTime? _focusFilterEnd;
  DateTime? _stressFilterStart;
  DateTime? _stressFilterEnd;
  DateTime? _eegFilterStart;
  DateTime? _eegFilterEnd;

  late final int _t0;
  late SharedPreferences _prefs;

  // Streaming guards
  DateTime _lastBLEData = DateTime.now();
  final Set<DateTime> _bleActiveMinutes = <DateTime>{};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _t0 = DateTime.now().millisecondsSinceEpoch;
    _initPrefsAndLoadData();

    _sub = widget.eegStream.listen((sample) {
      final now = DateTime.now();
      final seconds = (now.millisecondsSinceEpoch - _t0) / 1000.0;
      _lastBLEData = now;

      // Mark current minute active, and also previous minute to protect boundary jitter
      final currM = _minuteFloor(now);
      final prevM = currM.subtract(const Duration(minutes: 1));
      _bleActiveMinutes.add(currM);
      _bleActiveMinutes.add(prevM);

      for (int i = 0; i < 4; i++) {
        final ch = _channels[i];
        ch.add(FlSpot(seconds, sample[i]));
        if (ch.length > _maxPoints) ch.removeAt(0);
      }
    });

    _uiTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted) setState(() {});
    });

    _scheduleNextMinuteTick();

    widget.focusSeriesStream.listen((series) {
      if (!mounted) return;
      final now = DateTime.now();
      _lastBLEData = now;
      setState(() {
        for (final v in series) {
          final coerced = _coerceBinary(v);
          _addOrReplaceByMinute(_focusScores, _focusTimestamps, coerced, now);
        }
        _refreshLabels();
        _saveData();
      });
    });

    widget.stressSeriesStream.listen((series) {
      if (!mounted) return;
      final now = DateTime.now();
      _lastBLEData = now;
      setState(() {
        for (final v in series) {
          final coerced = _coerceBinary(v);
          _addOrReplaceByMinute(_stressScores, _stressTimestamps, coerced, now);
        }
        _refreshLabels();
        _saveData();
      });
    });
  }

  // ---------- helpers ----------
  DateTime _minuteFloor(DateTime t) =>
      DateTime(t.year, t.month, t.day, t.hour, t.minute);

  void _addOrReplaceByMinute(
      List<double> scores, List<DateTime> times, double value, DateTime t) {
    final m = _minuteFloor(t);
    if (times.isNotEmpty && _minuteFloor(times.last) == m) {
      scores[scores.length - 1] = value;
      times[times.length - 1] = m;
    } else {
      scores.add(value);
      times.add(m);
    }
  }

  double _coerceBinary(double v) {
    if (v == -1) return -1;
    return v >= 0.5 ? 1 : 0;
  }

  bool _hasEntryForMinute(List<DateTime> times, DateTime m) {
    if (times.isNotEmpty && _minuteFloor(times.last) == m) return true;
    for (final t in times) {
      if (_minuteFloor(t) == m) return true;
    }
    return false;
  }

  bool _isStreamingActive() {
    // consider streaming active if we saw BLE within the last 15s
    return DateTime.now().difference(_lastBLEData) <
        const Duration(seconds: 15);
  }

  void _backfillNoneStatesUpToNow() {
    final nowM = _minuteFloor(DateTime.now());

    DateTime? lastFocus =
        _focusTimestamps.isNotEmpty ? _minuteFloor(_focusTimestamps.last) : null;
    DateTime? lastStress =
        _stressTimestamps.isNotEmpty ? _minuteFloor(_stressTimestamps.last) : null;

    DateTime? lastAny;
    if (lastFocus == null) {
      lastAny = lastStress;
    } else if (lastStress == null) {
      lastAny = lastFocus;
    } else {
      lastAny = lastFocus.isAfter(lastStress) ? lastFocus : lastStress;
    }
    if (lastAny == null) return;

    var cursor = lastAny.add(const Duration(minutes: 1));
    while (!cursor.isAfter(nowM)) {
      // only backfill None if we did NOT have EEG that minute
      if (!_bleActiveMinutes.contains(cursor)) {
        _addOrReplaceByMinute(_focusScores, _focusTimestamps, -1, cursor);
        _addOrReplaceByMinute(_stressScores, _stressTimestamps, -1, cursor);
      }
      cursor = cursor.add(const Duration(minutes: 1));
    }
  }

  void _scheduleNextMinuteTick() {
    final now = DateTime.now();
    final nextMinute = DateTime(now.year, now.month, now.day, now.hour, now.minute)
        .add(const Duration(minutes: 1));
    final nextFire = nextMinute.add(const Duration(seconds: 3)); // grace
    final delay = nextFire.difference(now);

    _minuteTickTimer?.cancel();
    _minuteTickTimer = Timer(delay, () {
      _processMinuteBoundaryTick();
      _scheduleNextMinuteTick();
    });
  }

  void _processMinuteBoundaryTick() {
    // decide about the minute that just ended
    final prevMinute =
        _minuteFloor(DateTime.now().subtract(const Duration(minutes: 1)));

    final eegWasActive = _bleActiveMinutes.contains(prevMinute);
    final focusHasEntry = _hasEntryForMinute(_focusTimestamps, prevMinute);
    final stressHasEntry = _hasEntryForMinute(_stressTimestamps, prevMinute);

    // If streaming is active OR EEG was active in that minute → never insert None
    if (_isStreamingActive() || eegWasActive) {
      // nothing to do; analyzer/UI will fill the point or we leave it blank
    } else if (mounted && (!focusHasEntry || !stressHasEntry)) {
      setState(() {
        if (!focusHasEntry) {
          _addOrReplaceByMinute(_focusScores, _focusTimestamps, -1, prevMinute);
        }
        if (!stressHasEntry) {
          _addOrReplaceByMinute(_stressScores, _stressTimestamps, -1, prevMinute);
        }
        _refreshLabels();
        _saveData();
      });
    }

    // cleanup: keep last ~2h of EEG markers
    final cutoff = DateTime.now().subtract(const Duration(hours: 2));
    _bleActiveMinutes.removeWhere((m) => m.isBefore(cutoff));
  }

  void clearEEGData() {
    for (var ch in _channels) {
      ch.clear();
    }
    if (mounted) setState(() {});
  }

  Future<void> _clearFocusData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Focus Data'),
        content: const Text(
            'Are you sure you want to clear all focus data? This will replace all recorded states with "None" (inactive).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFBD9F72),
              foregroundColor: Colors.black,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        for (int i = 0; i < _focusScores.length; i++) {
          _focusScores[i] = -1;
        }
        _refreshLabels();
        _saveData();
      });
    }
  }

  Future<void> _clearStressData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Stress Data'),
        content: const Text(
            'Are you sure you want to clear all stress data? This will replace all recorded states with "None" (inactive).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFBD9F72),
              foregroundColor: Colors.black,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        for (int i = 0; i < _stressScores.length; i++) {
          _stressScores[i] = -1;
        }
        _refreshLabels();
        _saveData();
      });
    }
  }

  Future<void> _initPrefsAndLoadData() async {
    _prefs = await SharedPreferences.getInstance();
    final focusJson = _prefs.getString('analytics_focus_scores');
    final stressJson = _prefs.getString('analytics_stress_scores');
    final focusTimeJson = _prefs.getString('analytics_focus_timestamps');
    final stressTimeJson = _prefs.getString('analytics_stress_timestamps');

    if (focusJson != null) {
      final List<dynamic> stored = jsonDecode(focusJson);
      _focusScores = stored.map((e) => (e as num).toDouble()).toList();
    }
    if (stressJson != null) {
      final List<dynamic> stored = jsonDecode(stressJson);
      _stressScores = stored.map((e) => (e as num).toDouble()).toList();
    }
    if (focusTimeJson != null) {
      final List<dynamic> stored = jsonDecode(focusTimeJson);
      _focusTimestamps =
          stored.map((e) => DateTime.parse(e as String)).toList();
    }
    if (stressTimeJson != null) {
      final List<dynamic> stored = jsonDecode(stressTimeJson);
      _stressTimestamps =
          stored.map((e) => DateTime.parse(e as String)).toList();
    }

    // Snap to minute and (from now on) protect active minutes
    _focusTimestamps = _focusTimestamps.map(_minuteFloor).toList();
    _stressTimestamps = _stressTimestamps.map(_minuteFloor).toList();

    _backfillNoneStatesUpToNow();

    _refreshLabels();
    if (mounted) setState(() {});
  }

  void _saveData() {
    _prefs.setString('analytics_focus_scores', jsonEncode(_focusScores));
    _prefs.setString('analytics_stress_scores', jsonEncode(_stressScores));
    _prefs.setString(
        'analytics_focus_timestamps',
        jsonEncode(
            _focusTimestamps.map((e) => e.toIso8601String()).toList()));
    _prefs.setString(
        'analytics_stress_timestamps',
        jsonEncode(
            _stressTimestamps.map((e) => e.toIso8601String()).toList()));
  }

  void _refreshLabels() {
    final timestamps = _focusTimestamps
        .where((t) =>
            (_focusFilterStart == null || !t.isBefore(_focusFilterStart!)) &&
            (_focusFilterEnd == null || !t.isAfter(_focusFilterEnd!)))
        .toList();
    _minuteLabels = timestamps
        .map((t) =>
            "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}")
        .toList();
  }

  Future<void> _pickFilter(BuildContext context, String type) async {
    final now = DateTime.now();
    DateTime? start = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (start == null) return;

    TimeOfDay? startTime =
        await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (startTime == null) return;

    DateTime? end = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (end == null) return;

    TimeOfDay? endTime =
        await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (endTime == null) return;

    setState(() {
      final startDateTime = DateTime(start.year, start.month, start.day,
          startTime.hour, startTime.minute);
      final endDateTime = DateTime(
          end.year, end.month, end.day, endTime.hour, endTime.minute);

      if (type == "EEG") {
        _eegFilterStart = startDateTime;
        _eegFilterEnd = endDateTime;
      } else if (type == "Focus") {
        _focusFilterStart = startDateTime;
        _focusFilterEnd = endDateTime;
        _refreshLabels();
      } else if (type == "Stress") {
        _stressFilterStart = startDateTime;
        _stressFilterEnd = endDateTime;
        _refreshLabels();
      }
    });
  }

  List<DateTime> _generateMinuteTicks(DateTime start, DateTime end) {
    final ticks = <DateTime>[];
    var current =
        DateTime(start.year, start.month, start.day, start.hour, start.minute);
    while (current.isBefore(end) || current.isAtSameMomentAs(end)) {
      ticks.add(current);
      current = current.add(const Duration(minutes: 1));
    }
    return ticks;
  }

  @override
  void dispose() {
    _sub.cancel();
    _uiTimer?.cancel();
    _minuteTickTimer?.cancel();
    super.dispose();
  }

  Widget _buildEEGChart(BuildContext context) {
    final minX = _channels[0].isEmpty ? 0.0 : _channels[0].first.x;
    final maxX = _channels[0].isEmpty ? 1.0 : _channels[0].last.x;

    double minY = double.infinity, maxY = double.negativeInfinity;
    for (var ch in _channels) {
      for (var p in ch) {
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;
      }
    }
    if (minY == double.infinity) {
      minY = -2000;
      maxY = 2000;
    }

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Live Raw EEG",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () => _pickFilter(context, "EEG"),
                  child: const Text("Filter"),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
                child: LineChart(LineChartData(
              minX: minX,
              maxX: maxX,
              minY: minY,
              maxY: maxY,
              gridData: FlGridData(show: true),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles:
                      SideTitles(showTitles: true, reservedSize: 40),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (v, _) {
                      final millis = _t0 + (v * 1000).toInt();
                      final t =
                          DateTime.fromMillisecondsSinceEpoch(millis);
                      final label =
                          "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}";
                      return Text(label,
                          style: const TextStyle(fontSize: 10));
                    },
                  ),
                ),
                topTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineBarsData: List.generate(4, (i) {
                final colors = [
                  Colors.blue,
                  Colors.red,
                  Colors.green,
                  Colors.purple
                ];
                return LineChartBarData(
                  spots: _channels[i],
                  isCurved: false,
                  color: colors[i],
                  dotData: FlDotData(show: false),
                  barWidth: 2,
                );
              }),
              borderData: FlBorderData(show: true),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final millis = _t0 + (spot.x * 1000).toInt();
                      final t =
                          DateTime.fromMillisecondsSinceEpoch(millis);
                      final timeLabel =
                          "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";
                      return LineTooltipItem(
                        timeLabel,
                        const TextStyle(color: Colors.black),
                      );
                    }).toList();
                  },
                ),
              ),
            ))),
          ],
        ),
      ),
    );
  }

  Widget _buildBinaryLineChart(
      BuildContext context,
      List<double> data,
      List<DateTime> timestamps,
      String title,
      String lowLabel,
      String highLabel,
      Color lowColor,
      Color highColor) {
    final filterStart =
        title == "Focus" ? _focusFilterStart : _stressFilterStart;
    final filterEnd =
        title == "Focus" ? _focusFilterEnd : _stressFilterEnd;

    List<double> filteredData = [];
    List<DateTime> filteredTimestamps = [];

    for (int i = 0; i < data.length && i < timestamps.length; i++) {
      final timestamp = timestamps[i];
      bool includePoint = true;

      if (filterStart != null && timestamp.isBefore(filterStart)) {
        includePoint = false;
      }
      if (filterEnd != null && timestamp.isAfter(filterEnd)) {
        includePoint = false;
      }

      if (includePoint) {
        filteredData.add(data[i]);
        filteredTimestamps.add(timestamp);
      }
    }

    if (filteredData.isEmpty) {
      final now = DateTime.now();
      final start = filterStart ?? now.subtract(const Duration(hours: 1));
      final end = filterEnd ?? now;
      final ticks = _generateMinuteTicks(start, end);

      filteredData = List.filled(ticks.length, -1.0);
      filteredTimestamps = ticks;
    }

    final labels = filteredTimestamps
        .map((t) =>
            "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}")
        .toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => _pickFilter(context, title),
                      child: const Text("Filter"),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: title == "Focus"
                          ? _clearFocusData
                          : _clearStressData,
                      child: const Text("Clear Data"),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: filteredData.isEmpty
                      ? 1
                      : (filteredData.length - 1).toDouble(),
                  minY: 0,
                  maxY: 1,
                  gridData: FlGridData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        interval: 0.2,
                        getTitlesWidget: (value, _) {
                          if ((value - 0.2).abs() < 0.01) {
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 6),
                              child: Transform.rotate(
                                angle: -1.5708,
                                child: Text(lowLabel,
                                    style: const TextStyle(fontSize: 12),
                                    softWrap: false,
                                    overflow: TextOverflow.visible),
                              ),
                            );
                          } else if ((value - 0.5).abs() < 0.01) {
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 6),
                              child: Transform.rotate(
                                angle: -1.5708,
                                child: const Text("None",
                                    style: TextStyle(fontSize: 12),
                                    softWrap: false,
                                    overflow: TextOverflow.visible),
                              ),
                            );
                          } else if ((value - 0.8).abs() < 0.01) {
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 6),
                              child: Transform.rotate(
                                angle: -1.5708,
                                child: Text(highLabel,
                                    style: const TextStyle(fontSize: 12),
                                    softWrap: false,
                                    overflow: TextOverflow.visible),
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= labels.length) {
                            return const SizedBox();
                          }
                          return Text(labels[idx],
                              style: const TextStyle(fontSize: 10));
                        },
                      ),
                    ),
                    topTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (int i = 0; i < filteredData.length; i++)
                          FlSpot(
                              i.toDouble(),
                              filteredData[i] == -1
                                  ? 0.5
                                  : filteredData[i] == 1
                                      ? 0.8
                                      : 0.2),
                      ],
                      isCurved: false,
                      color: Colors.black,
                      barWidth: 2,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, idx) {
                          Color dotColor;
                          if (idx < filteredData.length &&
                              filteredData[idx] == -1) {
                            dotColor = Colors.grey;
                          } else {
                            final isHigh = idx < filteredData.length &&
                                filteredData[idx] == 1;
                            dotColor = isHigh ? highColor : lowColor;
                          }
                          return FlDotCirclePainter(
                            radius: 6,
                            strokeWidth: 3,
                            strokeColor: dotColor,
                            color: const Color(0xFFF3ECDE),
                          );
                        },
                      ),
                    )
                  ],
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: 0.35,
                        color: Colors.black,
                        strokeWidth: 1,
                        dashArray: [6, 4],
                      ),
                      HorizontalLine(
                        y: 0.65,
                        color: Colors.black,
                        strokeWidth: 1,
                        dashArray: [6, 4],
                      ),
                    ],
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final idx = spot.x.toInt();
                          if (idx >= 0 && idx < labels.length) {
                            return LineTooltipItem(
                              labels[idx],
                              const TextStyle(color: Colors.black),
                            );
                          }
                          return null;
                        }).whereType<LineTooltipItem>().toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF3ECDE),
      appBar: AppBar(
        title: const Text('Analytics'),
        backgroundColor: const Color(0xFFBD9F72),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildEEGChart(context),
              _buildBinaryLineChart(context, _focusScores, _focusTimestamps,
                  "Focus", "Distracted", "Focused", Colors.red, Colors.blue),
              _buildBinaryLineChart(context, _stressScores, _stressTimestamps,
                  "Stress", "Stressed", "Calm", Colors.orange, Colors.green),
            ],
          ),
        ),
      ),
    );
  }
}
