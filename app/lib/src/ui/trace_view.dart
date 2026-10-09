import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'monitor_controller.dart';

/// Scrolling seismograph trace of the band-passed acceleration.
class TraceView extends StatelessWidget {
  const TraceView({super.key, required this.trace});

  final TraceBuffer trace;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _TracePainter(
        trace,
        line: scheme.primary,
        grid: scheme.outlineVariant,
        label: scheme.onSurfaceVariant,
        version: trace.total,
      ),
      size: Size.infinite,
    );
  }
}

class _TracePainter extends CustomPainter {
  _TracePainter(
    this.trace, {
    required this.line,
    required this.grid,
    required this.label,
    required this.version,
  });

  final TraceBuffer trace;
  final Color line, grid, label;
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    canvas.drawLine(
      Offset(0, mid),
      Offset(size.width, mid),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );
    if (trace.length < 2) return;

    var peak = 0.0;
    for (var i = 0; i < trace.length; i++) {
      peak = math.max(peak, trace[i]);
    }
    // Don't zoom into pure sensor noise.
    final scale = math.max(peak, 0.05) * 1.2;

    // Draw magnitude mirrored around the centre line, like a drum recorder.
    final path = Path();
    final dx = size.width / (trace.capacity - 1);
    final x0 = size.width - (trace.length - 1) * dx;
    for (var i = 0; i < trace.length; i++) {
      final y = trace[i] / scale * mid * (i.isEven ? 1 : -1);
      final p = Offset(x0 + i * dx, mid - y);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: '±${scale.toStringAsFixed(2)} m/s²',
        style: TextStyle(color: label, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(4, 2));
  }

  @override
  bool shouldRepaint(_TracePainter old) =>
      old.version != version || old.line != line;
}
