import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'monitor_controller.dart';
import 'theme.dart';

/// Scrolling seismograph trace of the band-passed acceleration, drawn like
/// a glowing line on an instrument panel.
class TraceView extends StatelessWidget {
  const TraceView({super.key, required this.trace, required this.active, this.color = Palette.amber});

  final TraceBuffer trace;

  /// When false, only the grid and a resting baseline are drawn.
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _TracePainter(trace, active: active, color: color, version: trace.total),
        size: Size.infinite,
      );
}

class _TracePainter extends CustomPainter {
  _TracePainter(this.trace, {required this.active, required this.color, required this.version});

  final TraceBuffer trace;
  final bool active;
  final Color color;
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final gridPaint = Paint()
      ..color = Palette.grid
      ..strokeWidth = 1;

    // One vertical line per second (the buffer holds ten seconds).
    for (var i = 1; i < 10; i++) {
      final x = size.width * i / 10;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (final f in [0.25, 0.75]) {
      canvas.drawLine(Offset(0, size.height * f), Offset(size.width, size.height * f), gridPaint);
    }
    canvas.drawLine(
      Offset(0, mid),
      Offset(size.width, mid),
      Paint()
        ..color = Palette.outline
        ..strokeWidth = 1,
    );

    if (!active || trace.length < 2) return;

    var peak = 0.0;
    for (var i = 0; i < trace.length; i++) {
      peak = math.max(peak, trace[i]);
    }
    // Don't zoom into pure sensor noise.
    final scale = math.max(peak, 0.05) * 1.25;

    // Draw the shaking envelope mirrored around the centre line. A light
    // max-hold over a few samples keeps it readable at 50 samples a second.
    final dx = size.width / (trace.capacity - 1);
    final x0 = size.width - (trace.length - 1) * dx;
    final env = List<double>.generate(trace.length, (i) {
      var m = trace[i];
      for (var k = math.max(0, i - 2); k <= math.min(trace.length - 1, i + 2); k++) {
        m = math.max(m, trace[k]);
      }
      return math.min(m / scale, 1.0) * (mid - 4);
    });
    final top = Path(), bottom = Path();
    for (var i = 0; i < env.length; i++) {
      final x = x0 + i * dx;
      if (i == 0) {
        top.moveTo(x, mid - env[i]);
        bottom.moveTo(x, mid + env[i]);
      } else {
        top.lineTo(x, mid - env[i]);
        bottom.lineTo(x, mid + env[i]);
      }
    }
    final last = Offset(x0 + (env.length - 1) * dx, mid - env.last);

    final band = Path.from(top);
    for (var i = env.length - 1; i >= 0; i--) {
      band.lineTo(x0 + i * dx, mid + env[i]);
    }
    band.close();

    // Fade the oldest part of the trace into the panel.
    Shader fade(double alpha) => LinearGradient(
          colors: [color.withValues(alpha: 0), color.withValues(alpha: alpha)],
          stops: const [0, 0.35],
        ).createShader(Offset.zero & size);

    canvas.drawPath(band, Paint()..shader = fade(0.18));
    for (final edge in [top, bottom]) {
      canvas.drawPath(
        edge,
        Paint()
          ..shader = fade(0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawPath(
        edge,
        Paint()
          ..shader = fade(1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // The pen.
    canvas.drawCircle(
      last,
      7,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(last, 2.5, Paint()..color = color);

    final tp = TextPainter(
      text: TextSpan(
        text: '±${scale.toStringAsFixed(2)} m/s²',
        style: const TextStyle(fontFamily: mono, fontSize: 10, color: Palette.faint),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width - tp.width - 10, 8));
  }

  @override
  bool shouldRepaint(_TracePainter old) =>
      old.version != version || old.active != active || old.color != color;
}
