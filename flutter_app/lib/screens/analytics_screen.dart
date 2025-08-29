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
  Timer? _noneStateTimer; // Timer for inserting None states

  List<double> _focusScores = [];
  List<double> _stressScores = [];
  List<DateTime> _focusTimestamps = [];
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
  DateTime _lastBLEData = DateTime.now(); // Track last BLE data received

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _t0 = DateTime.now().millisecondsSinceEpoch;
    _initPrefsAndLoadData();

    _sub = widget.eegStream.listen((sample) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final seconds = (now - _t0) / 1000.0;
      _lastBLEData = DateTime.now(); // Update last BLE data timestamp

      for (int i = 0; i < 4; i++) {
        final ch = _channels[i];
        ch.add(FlSpot(seconds, sample[i]));
        if (ch.length > _maxPoints) ch.removeAt(0);
      }
    });

    _uiTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted) setState(() {});
    });

    // Timer to insert None states every minute when no BLE data
    _noneStateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _insertNoneStateIfNeeded();
    });

    widget.focusSeriesStream.listen((series) {
      if (mounted) {
        final now = DateTime.now();
        _lastBLEData = now; // Update last BLE data timestamp
        setState(() {
          _focusScores.addAll(series);
          _focusTimestamps.addAll(List.generate(series.length, (_) => now));
          _refreshLabels();
          _saveData();
        });
      }
    });

    widget.stressSeriesStream.listen((series) {
      if (mounted) {
        final now = DateTime.now();
        _lastBLEData = now; // Update last BLE data timestamp
        setState(() {
          _stressScores.addAll(series);
          _stressTimestamps.addAll(List.generate(series.length, (_) => now));
          _refreshLabels();
          _saveData();
        });
      }
    });
  }

  void _insertNoneStateIfNeeded() {
    final now = DateTime.now();
    final timeSinceLastBLE = now.difference(_lastBLEData);
    
    // If more than 1 minute has passed since last BLE data, insert None state (-1)
    if (timeSinceLastBLE.inMinutes >= 1) {
      if (mounted) {
        setState(() {
          _focusScores.add(-1); // -1 represents "None" state
          _stressScores.add(-1);
          _focusTimestamps.add(now);
          _stressTimestamps.add(now);
          _refreshLabels();
          _saveData();
        });
      }
    }
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
        content: const Text('Are you sure you want to clear all focus data? This will replace all recorded states with "None" (inactive).'),
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
        // Replace all focus scores with -1 (None state)
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
        content: const Text('Are you sure you want to clear all stress data? This will replace all recorded states with "None" (inactive).'),
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
        // Replace all stress scores with -1 (None state)
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
      _focusTimestamps = stored.map((e) => DateTime.parse(e as String)).toList();
    }
    if (stressTimeJson != null) {
      final List<dynamic> stored = jsonDecode(stressTimeJson);
      _stressTimestamps = stored.map((e) => DateTime.parse(e as String)).toList();
    }

    _refreshLabels();
    if (mounted) setState(() {});
  }

  void _saveData() {
    _prefs.setString('analytics_focus_scores', jsonEncode(_focusScores));
    _prefs.setString('analytics_stress_scores', jsonEncode(_stressScores));
    _prefs.setString('analytics_focus_timestamps',
        jsonEncode(_focusTimestamps.map((e) => e.toIso8601String()).toList()));
    _prefs.setString('analytics_stress_timestamps',
        jsonEncode(_stressTimestamps.map((e) => e.toIso8601String()).toList()));
  }

  void _refreshLabels() {
    List<DateTime> timestamps = _focusTimestamps
        .where((t) =>
            (_focusFilterStart == null || !t.isBefore(_focusFilterStart!)) &&
            (_focusFilterEnd == null || !t.isAfter(_focusFilterEnd!)))
        .toList();
    _minuteLabels = timestamps
        .map((t) => "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}")
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

    TimeOfDay? startTime = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (startTime == null) return;

    DateTime? end = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (end == null) return;

    TimeOfDay? endTime = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (endTime == null) return;

    setState(() {
      final startDateTime = DateTime(start.year, start.month, start.day, startTime.hour, startTime.minute);
      final endDateTime = DateTime(end.year, end.month, end.day, endTime.hour, endTime.minute);
      
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
    List<DateTime> ticks = [];
    DateTime current = DateTime(start.year, start.month, start.day, start.hour, start.minute);
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
    _noneStateTimer?.cancel();
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
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () => _pickFilter(context, "EEG"),
                  child: const Text("Filter"),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LineChart(
                LineChartData(
                  minX: minX,
                  maxX: maxX,
                  minY: minY,
                  maxY: maxY,
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        getTitlesWidget: (v, _) {
                          final millis = _t0 + (v * 1000).toInt();
                          final t = DateTime.fromMillisecondsSinceEpoch(millis);
                          final label =
                              "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}";
                          return Text(label, style: const TextStyle(fontSize: 10));
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  lineBarsData: List.generate(4, (i) {
                    final colors = [Colors.blue, Colors.red, Colors.green, Colors.purple];
                    return LineChartBarData(
                      spots: _channels[i],
                      isCurved: false,
                      color: colors[i],
                      dotData: FlDotData(show: false),
                      barWidth: 2,
                    );
                  }),
                  borderData: FlBorderData(show: true),

                  // 👇 NEW tooltip section
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final millis = _t0 + (spot.x * 1000).toInt();
                          final t = DateTime.fromMillisecondsSinceEpoch(millis);
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
                )
              ),
            ),
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
    
    // Get appropriate filter variables based on chart type
    DateTime? filterStart = title == "Focus" ? _focusFilterStart : _stressFilterStart;
    DateTime? filterEnd = title == "Focus" ? _focusFilterEnd : _stressFilterEnd;
    
    // Create filtered data with None states preserved
    List<double> filteredData = [];
    List<DateTime> filteredTimestamps = [];
    
    // Filter existing data based on timestamp ranges
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
    
    // If no data matches the filter or no data exists at all, generate minute ticks for the range
    if (filteredData.isEmpty) {
      final now = DateTime.now();
      final start = filterStart ?? now.subtract(const Duration(hours: 1));
      final end = filterEnd ?? now;
      final ticks = _generateMinuteTicks(start, end);
      
      filteredData = List.filled(ticks.length, -1.0); // All None states
      filteredTimestamps = ticks;
    }

    final labels = filteredTimestamps
        .map((t) => "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}")
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
                      onPressed: title == "Focus" ? _clearFocusData : _clearStressData,
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
                  maxX: filteredData.isEmpty ? 1 : (filteredData.length - 1).toDouble(),
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
                              padding: const EdgeInsets.symmetric(vertical: 6),
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
                              padding: const EdgeInsets.symmetric(vertical: 6),
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
                              padding: const EdgeInsets.symmetric(vertical: 6),
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
                          if (idx < 0 || idx >= labels.length) return const SizedBox();
                          return Text(labels[idx], style: const TextStyle(fontSize: 10));
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (int i = 0; i < filteredData.length; i++)
                          FlSpot(
                              i.toDouble(),
                              filteredData[i] == -1
                                  ? 0.5 // None state
                                  : filteredData[i] == 1
                                      ? 0.8
                                      : 0.2), // High/Low states
                      ],
                      isCurved: false,
                      color: Colors.black,
                      barWidth: 2,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, idx) {
                          Color dotColor;
                          if (idx < filteredData.length && filteredData[idx] == -1) {
                            dotColor = Colors.grey; // None state
                          } else {
                            final isHigh =
                                idx < filteredData.length && filteredData[idx] == 1;
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

                  // 👇 NEW tooltip section
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
                )
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