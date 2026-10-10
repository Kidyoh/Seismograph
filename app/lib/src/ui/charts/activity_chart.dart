import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/activity.dart';
import '../theme.dart';
import 'axis.dart';
import 'scale.dart';

/// Background vibration minute by minute through the night, with a rule at
/// each detection.
class ActivityChart extends StatelessWidget {
  const ActivityChart({super.key, required this.points, required this.detections});

  final List<ActivityPoint> points;
  final List<DateTime> detections;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _Painter(points, detections),
        size: Size.infinite,
      );
}

class _Painter extends CustomPainter {
  _Painter(this.points, this.detections);

  final List<ActivityPoint> points;
  final List<DateTime> detections;

  static const _margin = ChartMargin(left: 44);

  @override
  void paint(Canvas canvas, Size size) {
    final plot = _margin.plot(size);
    final axis = AxisPainter(canvas);

    final t0 = points.first.time.millisecondsSinceEpoch.toDouble();
    // At least an hour wide so a fresh night doesn't look stretched.
    final t1 = math.max(points.last.time.millisecondsSinceEpoch.toDouble() + 60000, t0 + 3600000);
    final x = LinearScale(t0, t1, plot.left, plot.right);
    final maxRms = points.map((p) => p.rms).fold(0.0, math.max);
    final y = LinearScale(0, math.max(maxRms, 0.005), plot.bottom, plot.top).nice(3);

    final yTicks = y.ticks(3);
    axis.gridY(plot, [for (final t in yTicks) if (t > 0) y(t)]);
    axis.left(plot, [for (final t in yTicks) (y(t), formatTick(t, yTicks))]);
    axis.bottom(plot, _hourTicks(t0, t1, x));

    final rule = Paint()
      ..color = Palette.red.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    for (final d in detections) {
      final px = x(d.millisecondsSinceEpoch.toDouble());
      if (px < plot.left || px > plot.right) continue;
      canvas.drawLine(Offset(px, plot.top), Offset(px, plot.bottom), rule);
      canvas.drawCircle(Offset(px, plot.top + 2), 2.5, Paint()..color = Palette.red);
    }

    // Break the line where listening paused for more than a few minutes.
    final line = Path();
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final px = x(p.time.millisecondsSinceEpoch.toDouble() + 30000);
      final py = y(p.rms);
      final gap = i > 0 && p.time.difference(points[i - 1].time) > const Duration(minutes: 3);
      i == 0 || gap ? line.moveTo(px, py) : line.lineTo(px, py);
    }
    canvas.save();
    canvas.clipRect(plot.inflate(1));
    canvas.drawPath(
      line,
      Paint()
        ..color = Palette.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  /// Ticks on whole hours, spaced so there are at most six.
  List<(double, String)> _hourTicks(double t0, double t1, LinearScale x) {
    final hours = (t1 - t0) / 3600000;
    final every = hours <= 6 ? 1 : hours <= 12 ? 2 : 3;
    final start = DateTime.fromMillisecondsSinceEpoch(t0.toInt());
    var t = DateTime(start.year, start.month, start.day, start.hour).add(const Duration(hours: 1));
    final ticks = <(double, String)>[];
    while (t.millisecondsSinceEpoch <= t1) {
      if (t.hour % every == 0) {
        ticks.add((x(t.millisecondsSinceEpoch.toDouble()), '${t.hour.toString().padLeft(2, '0')}:00'));
      }
      t = t.add(const Duration(hours: 1));
    }
    return ticks;
  }

  @override
  bool shouldRepaint(_Painter old) => old.points != points || old.detections != detections;
}
