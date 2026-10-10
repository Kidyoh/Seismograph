import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../monitor_controller.dart';
import '../theme.dart';
import 'axis.dart';
import 'scale.dart';

/// The last ten seconds of shaking as a line chart with axes.
class LiveTraceChart extends StatelessWidget {
  const LiveTraceChart({super.key, required this.trace, required this.active, this.color = Palette.amber});

  final TraceBuffer trace;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _Painter(trace, active, color, trace.total),
        size: Size.infinite,
      );
}

class _Painter extends CustomPainter {
  _Painter(this.trace, this.active, this.color, this.version);

  final TraceBuffer trace;
  final bool active;
  final Color color;
  final int version;

  static const _margin = ChartMargin(left: 40);

  @override
  void paint(Canvas canvas, Size size) {
    final plot = _margin.plot(size);
    final axis = AxisPainter(canvas);

    var peak = 0.0;
    if (active) {
      for (var i = 0; i < trace.length; i++) {
        peak = math.max(peak, trace[i]);
      }
    }
    // Don't zoom into sensor noise: always show at least ±0.02 m/s².
    final y = LinearScale(0, math.max(peak, 0.02), plot.bottom, plot.top).nice(3);
    final x = LinearScale(-10, 0, plot.left, plot.right);

    final yTicks = y.ticks(3);
    axis.gridY(plot, [for (final t in yTicks) if (t > 0) y(t)]);
    axis.left(plot, [for (final t in yTicks) (y(t), formatTick(t, yTicks))]);
    axis.bottom(plot, [
      for (final s in [-10, -8, -6, -4, -2, 0]) (x(s.toDouble()), s == 0 ? 'now' : '${s}s'),
    ]);

    if (!active || trace.length < 2) return;

    // A light max-hold over five samples (0.1 s) keeps the line readable.
    final n = trace.length;
    final dt = 10 / (trace.capacity - 1);
    final line = Path();
    for (var i = 0; i < n; i++) {
      var m = trace[i];
      for (var k = math.max(0, i - 2); k <= math.min(n - 1, i + 2); k++) {
        m = math.max(m, trace[k]);
      }
      final px = x(-(n - 1 - i) * dt);
      final py = y(m);
      i == 0 ? line.moveTo(px, py) : line.lineTo(px, py);
    }
    final area = Path.from(line)
      ..lineTo(plot.right, plot.bottom)
      ..lineTo(x(-(n - 1) * dt), plot.bottom)
      ..close();

    canvas.save();
    canvas.clipRect(plot);
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.08));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Painter old) => old.version != version || old.active != active || old.color != color;
}
