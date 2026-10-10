import 'dart:math' as math;

/// A linear scale and tick generator modelled on d3-scale's `scaleLinear`.
class LinearScale {
  LinearScale(this.d0, this.d1, this.r0, this.r1);

  final double d0, d1; // domain
  final double r0, r1; // range, in pixels

  double call(double v) {
    if (d1 == d0) return (r0 + r1) / 2;
    return r0 + (v - d0) / (d1 - d0) * (r1 - r0);
  }

  /// About [count] round tick values inside the domain, like `scale.ticks()`.
  List<double> ticks([int count = 5]) => niceTicks(d0, d1, count);

  /// A copy with the domain extended to round values, like `scale.nice()`.
  LinearScale nice([int count = 5]) {
    final step = tickIncrement(d0, d1, count);
    if (step <= 0 || !step.isFinite) return this;
    return LinearScale(
      (d0 / step).floor() * step,
      (d1 / step).ceil() * step,
      r0,
      r1,
    );
  }
}

/// Step between ticks: 1, 2 or 5 times a power of ten, as in d3-array.
double tickIncrement(double start, double stop, int count) {
  final raw = (stop - start).abs() / math.max(count, 1);
  if (raw == 0 || !raw.isFinite) return 0;
  final power = (math.log(raw) / math.ln10).floor();
  final error = raw / math.pow(10, power);
  final factor = error >= math.sqrt(50)
      ? 10
      : error >= math.sqrt(10)
          ? 5
          : error >= math.sqrt2
              ? 2
              : 1;
  return factor * math.pow(10, power).toDouble();
}

List<double> niceTicks(double start, double stop, int count) {
  final step = tickIncrement(start, stop, count);
  if (step == 0) return [start];
  final first = (start / step).ceil();
  final last = (stop / step).floor();
  // Rebuild from integers to avoid 0.30000000000000004.
  return [for (var i = first; i <= last; i++) _round(i * step, step)];
}

double _round(double v, double step) {
  final decimals = math.max(0, -(math.log(step) / math.ln10).floor());
  return double.parse(v.toStringAsFixed(decimals));
}

/// Formats a tick with as many decimals as its step needs.
String formatTick(double v, List<double> ticks) {
  if (ticks.length < 2) return _trim(v.toStringAsFixed(3));
  final step = (ticks[1] - ticks[0]).abs();
  final decimals = math.max(0, -(math.log(step) / math.ln10).floor());
  return v.toStringAsFixed(decimals);
}

String _trim(String s) => s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
