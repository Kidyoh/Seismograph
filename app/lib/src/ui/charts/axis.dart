import 'package:flutter/material.dart';

import '../theme.dart';

/// Space around the plot area, like the d3 margin convention.
class ChartMargin {
  const ChartMargin({this.top = 10, this.right = 12, this.bottom = 24, this.left = 44});

  final double top, right, bottom, left;

  Rect plot(Size size) => Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
}

/// Draws axes and gridlines in the style of d3-axis: a 1 px domain line,
/// short outward ticks and small labels.
class AxisPainter {
  AxisPainter(this.canvas);

  final Canvas canvas;

  static const _tickSize = 4.0;
  static final _line = Paint()
    ..color = Palette.outline
    ..strokeWidth = 1;
  static final _grid = Paint()
    ..color = Palette.grid
    ..strokeWidth = 1;
  static const _labelStyle = TextStyle(fontFamily: mono, fontSize: 9.5, color: Palette.faint);

  /// Horizontal gridlines across [plot] at each y tick.
  void gridY(Rect plot, List<double> ys) {
    for (final y in ys) {
      final py = y.roundToDouble() + 0.5;
      canvas.drawLine(Offset(plot.left, py), Offset(plot.right, py), _grid);
    }
  }

  /// Left axis. [ticks] pairs a pixel y with its label.
  void left(Rect plot, List<(double, String)> ticks) {
    final x = plot.left.roundToDouble() - 0.5;
    canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), _line);
    for (final (y, label) in ticks) {
      canvas.drawLine(Offset(x - _tickSize, y), Offset(x, y), _line);
      _text(label, Offset(x - _tickSize - 3, y), Alignment.centerRight);
    }
  }

  /// Bottom axis. [ticks] pairs a pixel x with its label.
  void bottom(Rect plot, List<(double, String)> ticks) {
    final y = plot.bottom.roundToDouble() + 0.5;
    canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), _line);
    for (final (x, label) in ticks) {
      canvas.drawLine(Offset(x, y), Offset(x, y + _tickSize), _line);
      _text(label, Offset(x, y + _tickSize + 2), Alignment.topCenter);
    }
  }

  void _text(String s, Offset at, Alignment align) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: _labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      Alignment.centerRight => -tp.width,
      Alignment.topCenter => -tp.width / 2,
      _ => 0.0,
    };
    final dy = align == Alignment.centerRight ? -tp.height / 2 : 0.0;
    tp.paint(canvas, at + Offset(dx, dy));
  }
}
