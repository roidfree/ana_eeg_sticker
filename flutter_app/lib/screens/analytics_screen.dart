// lib/screens/analytics_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class AnalyticsScreen extends StatefulWidget {
  /// Stream of raw 4-channel EEG samples at ~26 Hz
  final Stream<List<double>> eegStream;
  const AnalyticsScreen({required this.eegStream, super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  static const int _maxPoints = 200;    // keep last ~8 seconds of data
  final List<List<FlSpot>> _channels =
      List.generate(4, (_) => <FlSpot>[]);
  late StreamSubscription<List<double>> _sub;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _sub = widget.eegStream.listen((sample) {
      setState(() {
        for (var i = 0; i < 4; i++) {
          final ch = _channels[i];
          ch.add(FlSpot(_t, sample[i]));
          if (ch.length > _maxPoints) ch.removeAt(0);
        }
        _t += 1 / 26;  // advance time by sampling period
      });
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // determine visible window
    final minX = _channels[0].isEmpty ? 0.0 : _channels[0].first.x;
    final maxX = _channels[0].isEmpty ? 1.0 : _channels[0].last.x;
    // pick overall Y-range from data (or default ±2000)
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (var ch in _channels) {
      for (var p in ch) {
        minY = p.y < minY ? p.y : minY;
        maxY = p.y > maxY ? p.y : maxY;
      }
    }
    if (minY == double.infinity) {
      minY = -2000;
      maxY =  2000;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Raw EEG Streams'),
        backgroundColor: const Color(0xFFBD9F72),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: LineChart(
          LineChartData(
            minX: minX,
            maxX: maxX,
            minY: minY,
            maxY: maxY,
            gridData: FlGridData(show: true),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (v, _) => Text(v.toInt().toString()),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: (maxX - minX) / 5,
                  getTitlesWidget: (v, _) =>
                      Text('${(v).toStringAsFixed(1)}s'),
                ),
              ),
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
          ),
        ),
      ),
    );
  }
}
