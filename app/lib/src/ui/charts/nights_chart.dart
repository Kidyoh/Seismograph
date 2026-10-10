import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/detection_record.dart';
import '../theme.dart';
import 'axis.dart';
import 'scale.dart';

/// Detections per night over the last [nights] nights, real and test
/// stacked.
class NightsChart extends StatelessWidget {
  const NightsChart({super.key, required this.history, this.nights = 14});

  final List<DetectionRecord> history;
  final int nights;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _Painter(history, nights, DateTime.now()),
        size: Size.infinite,
      );
}

/// The evening a night started on, so 03:00 counts toward the night before.
DateTime nightOf(DateTime t) {
  final shifted = t.subtract(const Duration(hours: 12));
  return DateTime(shifted.year, shifted.month, shifted.day);
}

class _Painter extends CustomPainter {
  _Painter(this.history, this.nights, this.now);

  final List<DetectionRecord> history;
  final int nights;
  final DateTime now;

  static const _margin = ChartMargin(left: 28);

  @override
  void paint(Canvas canvas, Size size) {
    final plot = _margin.plot(size);
    final axis = AxisPainter(canvas);

    final last = nightOf(now);
    final days = [for (var i = nights - 1; i >= 0; i--) DateTime(last.year, last.month, last.day - i)];
    final real = List.filled(nights, 0), test = List.filled(nights, 0);
    for (final r in history) {
      final i = days.indexOf(nightOf(r.onset));
      if (i < 0) continue;
      r.simulated ? test[i]++ : real[i]++;
    }
    final maxCount = [for (var i = 0; i < nights; i++) real[i] + test[i]].fold(0, math.max);

    // Integer ticks only.
    final top = math.max(maxCount, 2).toDouble();
    final y = LinearScale(0, top, plot.bottom, plot.top).nice(2);
    final yTicks = y.ticks(2).where((t) => t == t.roundToDouble()).toList();
    axis.gridY(plot, [for (final t in yTicks) if (t > 0) y(t)]);
    axis.left(plot, [for (final t in yTicks) (y(t), t.toInt().toString())]);

    // Band scale with d3's default padding.
    final band = plot.width / nights;
    final barW = band * 0.6;
    double cx(int i) => plot.left + band * (i + 0.5);
    axis.bottom(plot, [
      for (var i = 0; i < nights; i++)
        if ((nights - 1 - i) % 3 == 0) (cx(i), i == nights - 1 ? 'last' : '${days[i].day}/${days[i].month}'),
    ]);

    for (var i = 0; i < nights; i++) {
      final left = cx(i) - barW / 2;
      final realTop = y(real[i].toDouble());
      final testTop = y((real[i] + test[i]).toDouble());
      if (real[i] > 0) {
        canvas.drawRect(Rect.fromLTRB(left, realTop, left + barW, plot.bottom), Paint()..color = Palette.amber);
      }
      if (test[i] > 0) {
        canvas.drawRect(
          Rect.fromLTRB(left, testTop, left + barW, realTop),
          Paint()..color = Palette.teal.withValues(alpha: 0.55),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Painter old) => old.history != history || old.nights != nights;
}
