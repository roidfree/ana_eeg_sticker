import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  static List<FlSpot> focusData = [];
  static List<FlSpot> stressData = [];
  static Map<String, List<FlSpot>> brainWaveData = {
    'Delta': [], 'Theta': [], 'Alpha': [], 'Beta': [], 'Gamma': [],
  };

  Timer? _timer;
  int secondCounter = 0;
  List<String> selectedWaves = ['Delta', 'Theta', 'Alpha', 'Beta', 'Gamma'];

  // Individual zoom bounds
  double focusMinX = 0, focusMaxX = 60;
  double stressMinX = 0, stressMaxX = 60;
  double waveMinX = 0, waveMaxX = 60;

  @override
  void initState() {
    super.initState();
    loadData();
    startStreamingData();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void startStreamingData() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      final xVal = secondCounter / 30;
      setState(() {
        focusData.add(FlSpot(xVal, Random().nextBool() ? 1 : 0));
        stressData.add(FlSpot(xVal, Random().nextBool() ? 1 : 0));
        for (var key in brainWaveData.keys) {
          brainWaveData[key]!
              .add(FlSpot(xVal, (Random().nextDouble() * 10) - 5));
        }
        secondCounter += 30;
        saveData();
      });
    });
  }

  void resetData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    setState(() {
      focusData.clear();
      stressData.clear();
      for (var key in brainWaveData.keys) brainWaveData[key]!.clear();
      secondCounter = 0;
      focusMinX = stressMinX = waveMinX = 0;
      focusMaxX = stressMaxX = waveMaxX = 60;
    });
    startStreamingData();
  }

  Future<void> saveData() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('focusData', jsonEncode(
        focusData.map((e) => [e.x, e.y]).toList()));
    prefs.setString('stressData', jsonEncode(
        stressData.map((e) => [e.x, e.y]).toList()));
    for (var key in brainWaveData.keys) {
      prefs.setString(key, jsonEncode(
          brainWaveData[key]!.map((e) => [e.x, e.y]).toList()));
    }
  }

  Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      focusData = (jsonDecode(prefs.getString('focusData') ?? '[]')
          as List)
          .map((e) => FlSpot(
              (e[0] as num).toDouble(), (e[1] as num).toDouble()))
          .toList();
      stressData = (jsonDecode(prefs.getString('stressData') ?? '[]')
          as List)
          .map((e) => FlSpot(
              (e[0] as num).toDouble(), (e[1] as num).toDouble()))
          .toList();
      for (var key in brainWaveData.keys) {
        brainWaveData[key] = (jsonDecode(prefs.getString(key) ?? '[]')
            as List)
            .map((e) => FlSpot(
                (e[0] as num).toDouble(), (e[1] as num).toDouble()))
            .toList();
      }
    });
  }

  String timeLabel(double x) {
    final ago = max(0, (focusData.length * 30) - x.toInt() * 30);
    final t = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 1))
        .subtract(Duration(seconds: ago));
    return DateFormat('HH:mm').format(t);
  }

  // Scale handler with reduced sensitivity
  void _onScale(ScaleUpdateDetails d, double minX, double maxX,
      void Function(double,double) update) {
    final raw = 1 / d.scale;
    final factor = 1 + (raw - 1) * 0.01;
    final mid = (minX + maxX) / 2;
    final span = (maxX - minX) * factor;
    update(max(0, mid - span/2), mid + span/2);
  }

  Widget focusGraph() {
    final disp = focusData
        .where((p) => p.x >= focusMinX && p.x <= focusMaxX)
        .toList();
    return GestureDetector(
      onScaleUpdate: (d) => setState(() =>
          _onScale(d, focusMinX, focusMaxX, (lo,hi) {
            focusMinX = lo; focusMaxX = hi;
          })
      ),
      child: Column(
        children: [
          const Text('🎯 Focus',
              style: TextStyle(fontSize:22, fontWeight: FontWeight.bold)),
          Row(children: [
            IconButton(
              icon: const Icon(Icons.remove),
              onPressed: () => setState(() {
                focusMinX = max(0, focusMinX - 5);
                focusMaxX += 5;
              }),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => setState(() {
                focusMinX += 5;
                focusMaxX = max(focusMinX + 5, focusMaxX - 5);
              }),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: resetData,
              icon: const Icon(Icons.refresh),
              label: const Text('Reset'),
            ),
          ]),
          Expanded(
            child: FractionallySizedBox(
              widthFactor: 1.0,
              alignment: Alignment.centerLeft,
              child: BarChart(
                BarChartData(
                  barGroups: disp.map((e) =>
                      BarChartGroupData(x: e.x.toInt(), barRods: [
                        BarChartRodData(fromY: 0.5, toY: 1, color: Colors.blue, width: 6),
                        BarChartRodData(fromY: 0, toY: 0.5, color: Colors.red, width: 6),
                      ])).toList(),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles:false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles:false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 6,
                        getTitlesWidget: (v, _) => Text(timeLabel(v)),
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 0.5,
                        reservedSize: 40,
                        getTitlesWidget: (v, _) {
                          if (v == 0.5) {
                            return Transform.translate(
                              offset: const Offset(8, 0),
                              child: Transform.rotate(
                                angle: math.pi / 2,
                                child: const Text(
                                  'Focused <--> Distracted',
                                  softWrap: false,
                                  overflow: TextOverflow.visible,
                                  maxLines: 1,
                                ),
                                alignment: Alignment.center,
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ),
                  gridData: FlGridData(show: true),
                ),
              ),
            ),
          ),
          const Padding(padding: EdgeInsets.all(8), child: Text('Time')),
        ],
      ),
    );
  }

  Widget stressGraph() {
    final disp = stressData
        .where((p) => p.x >= stressMinX && p.x <= stressMaxX)
        .toList();
    return GestureDetector(
      onScaleUpdate: (d) => setState(() =>
          _onScale(d, stressMinX, stressMaxX, (lo,hi) {
            stressMinX = lo; stressMaxX = hi;
          })
      ),
      child: Column(
        children: [
          const Text('⚠️ Stress',
              style: TextStyle(fontSize:22, fontWeight: FontWeight.bold)),
          Row(children: [
            IconButton(
              icon: const Icon(Icons.remove),
              onPressed: () => setState(() {
                stressMinX = max(0, stressMinX - 5);
                stressMaxX += 5;
              }),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => setState(() {
                stressMinX += 5;
                stressMaxX = max(stressMinX + 5, stressMaxX - 5);
              }),
            ),
          ]),
          Expanded(
            child: FractionallySizedBox(
              widthFactor: 1.0,
              alignment: Alignment.centerLeft,
              child: BarChart(
                BarChartData(
                  barGroups: disp.map((e) =>
                      BarChartGroupData(x: e.x.toInt(), barRods: [
                        BarChartRodData(fromY: 0.5, toY: 1, color: Colors.green, width: 6),
                        BarChartRodData(fromY: 0, toY: 0.5, color: Colors.red, width: 6),
                      ])).toList(),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles:false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles:false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 6,
                        getTitlesWidget: (v, _) => Text(timeLabel(v)),
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 0.5,
                        reservedSize: 40,
                        getTitlesWidget: (v, _) {
                          if (v == 0.5) {
                            return Transform.translate(
                              offset: const Offset(8, 0),
                              child: Transform.rotate(
                                angle: math.pi / 2,
                                child: const Text(
                                  'Calm <--> Stressed',
                                  softWrap: false,
                                  overflow: TextOverflow.visible,
                                  maxLines: 1,
                                ),
                                alignment: Alignment.center,
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ),
                  gridData: FlGridData(show: true),
                ),
              ),
            ),
          ),
          const Padding(padding: EdgeInsets.all(8), child: Text('Time')),
        ],
      ),
    );
  }

  Widget brainWaveGraph() {
    final filtered = <String, List<FlSpot>>{};
    for (var k in brainWaveData.keys) {
      filtered[k] = brainWaveData[k]!
          .where((p) => p.x >= waveMinX && p.x <= waveMaxX)
          .toList();
    }
    return GestureDetector(
      onScaleUpdate: (d) => setState(() =>
          _onScale(d, waveMinX, waveMaxX, (lo,hi) {
            waveMinX = lo; waveMaxX = hi;
          })
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('🧠 Raw Brain Waves',
                  style: TextStyle(fontSize:22, fontWeight: FontWeight.bold)),
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: () => setState(() {
                    waveMinX = max(0, waveMinX - 5);
                    waveMaxX += 5;
                  }),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => setState(() {
                    waveMinX += 5;
                    waveMaxX = max(waveMinX + 5, waveMaxX - 5);
                  }),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.tune),
                  itemBuilder: (_) => brainWaveData.keys.map((wave) {
                    final chk = selectedWaves.contains(wave);
                    return CheckedPopupMenuItem(
                        value: wave, checked: chk, child: Text(wave));
                  }).toList(),
                  onSelected: (w) => setState(() {
                    if (selectedWaves.contains(w)) {
                      selectedWaves.remove(w);
                    } else {
                      selectedWaves.add(w);
                    }
                  }),
                ),
              ]),
            ],
          ),
          Expanded(
            child: FractionallySizedBox(
              widthFactor: 0.95,
              alignment: Alignment.centerLeft,
              child: LineChart(
                LineChartData(
                  minY: -5, maxY: 5,
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles:false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles:false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 6,
                        getTitlesWidget: (v, _) => Text(timeLabel(v)),
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) => Text('${v.toStringAsFixed(1)} V'),
                        reservedSize: 60,
                      ),
                    ),
                  ),
                  gridData: FlGridData(show: true),
                  lineBarsData: selectedWaves.map((w) {
                    final clr = {
                      'Delta': Colors.indigo,
                      'Theta': Colors.teal,
                      'Alpha': Colors.orange,
                      'Beta': Colors.purple,
                      'Gamma': Colors.green,
                    }[w]!;
                    return LineChartBarData(
                      spots: filtered[w]!,
                      isCurved: true,
                      color: clr,
                      barWidth: 2,
                      dotData: FlDotData(show: false),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          const Padding(padding: EdgeInsets.all(8), child: Text('Time')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PageView(
          scrollDirection: Axis.vertical,
          children: [focusGraph(), stressGraph(), brainWaveGraph()],
        ),
      ),
    );
  }
}
