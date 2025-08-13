// ignore_for_file: deprecated_member_use, unnecessary_string_interpolations

import 'package:flutter/material.dart';
import 'dart:ui' as ui;

class LineSeries {
  LineSeries({required this.values, required this.color, required this.label});
  final List<double> values; // 0..1
  final Color color;
  final String label;
}

class SimpleLineChart extends StatelessWidget {
  const SimpleLineChart({
    super.key,
    required this.series,
    this.maxPoints = 60,
    this.title,
    this.yMin = 0,
    this.yMax = 1,
  });

  final List<LineSeries> series;
  final int maxPoints;
  final String? title;
  final double yMin;
  final double yMax;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.6,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: CustomPaint(
            painter: _ChartPainter(series, maxPoints, yMin, yMax, Theme.of(context).textTheme),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(title!, style: Theme.of(context).textTheme.titleMedium),
                  ),
                const Spacer(),
                _Legend(series: series),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.series});
  final List<LineSeries> series;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        for (final s in series)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 14, height: 3, color: s.color),
              const SizedBox(width: 6),
              Text(s.label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.series, this.maxPoints, this.yMin, this.yMax, this.textTheme);

  final List<LineSeries> series;
  final int maxPoints;
  final double yMin;
  final double yMax;
  final TextTheme textTheme;

  @override
  void paint(Canvas canvas, Size size) {
    final padding = const EdgeInsets.fromLTRB(36, 8, 8, 24);
    final chartRect = Rect.fromLTWH(
      padding.left,
      padding.top,
      size.width - padding.left - padding.right,
      size.height - padding.top - padding.bottom,
    );

    final axisPaint = Paint()
      ..color = Colors.grey.withOpacity(0.5)
      ..strokeWidth = 1;

    // Axes
    canvas.drawLine(
      Offset(chartRect.left, chartRect.bottom),
      Offset(chartRect.right, chartRect.bottom),
      axisPaint,
    );
    canvas.drawLine(
      Offset(chartRect.left, chartRect.top),
      Offset(chartRect.left, chartRect.bottom),
      axisPaint,
    );

    // Y ticks: 0, 0.5, 1.0
    for (final y in [yMin, (yMin + yMax) / 2, yMax]) {
      final ty = _mapY(y, chartRect);
      final p = Paint()..color = Colors.grey.withOpacity(0.25)..strokeWidth = 1;
      canvas.drawLine(Offset(chartRect.left, ty), Offset(chartRect.right, ty), p);

      final tp = _textPainter('${y.toStringAsFixed(1)}', textTheme.labelSmall!);
      tp.layout();
      tp.paint(canvas, Offset(chartRect.left - tp.width - 6, ty - tp.height / 2));
    }

    // Series
    for (final s in series) {
      final path = Path();
      final values = s.values.takeLast(maxPoints);
      if (values.isEmpty) continue;
      final n = values.length;
      for (int i = 0; i < n; i++) {
        final x = chartRect.left + (n == 1 ? 0 : (chartRect.width * i / (n - 1)));
        final y = _mapY(values[i], chartRect);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = s.color;
      canvas.drawPath(path, paint);
    }

    // X labels: minutes index (last, -10, -20)
    final labelStyle = textTheme.labelSmall!;
    for (final frac in [0.0, 0.5, 1.0]) {
      final x = chartRect.left + chartRect.width * frac;
      final tp = _textPainter(frac == 1.0 ? 'now' : (frac == 0.5 ? '−mid' : '−old'), labelStyle);
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, chartRect.bottom + 4));
    }
  }

  double _mapY(double v, Rect r) {
    final t = ((v - yMin) / (yMax - yMin)).clamp(0.0, 1.0);
    return r.bottom - t * r.height;
  }

  TextPainter _textPainter(String s, TextStyle style) {
    return TextPainter(
      text: TextSpan(text: s, style: style.copyWith(color: Colors.grey[700])),
      textDirection: ui.TextDirection.ltr,
    );
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.series != series || oldDelegate.maxPoints != maxPoints || oldDelegate.yMin != yMin || oldDelegate.yMax != yMax;
}

extension _TakeLast<T> on List<T> {
  List<T> takeLast(int k) {
    if (isEmpty) return <T>[];
    if (length <= k) return List<T>.from(this);
    return sublist(length - k);
  }
}
