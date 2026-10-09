import 'dart:math' as math;

/// Second-order (biquad) IIR filter, Direct Form I.
///
/// Coefficients follow the RBJ Audio EQ Cookbook.
class Biquad {
  Biquad._(this._b0, this._b1, this._b2, this._a1, this._a2);

  /// Butterworth high-pass at [cutoffHz] for a signal sampled at [sampleRateHz].
  factory Biquad.highPass(double cutoffHz, double sampleRateHz) {
    final w0 = 2 * math.pi * cutoffHz / sampleRateHz;
    final alpha = math.sin(w0) / (2 * math.sqrt1_2);
    final cosW0 = math.cos(w0);
    final a0 = 1 + alpha;
    return Biquad._(
      (1 + cosW0) / 2 / a0,
      -(1 + cosW0) / a0,
      (1 + cosW0) / 2 / a0,
      -2 * cosW0 / a0,
      (1 - alpha) / a0,
    );
  }

  /// Butterworth low-pass at [cutoffHz] for a signal sampled at [sampleRateHz].
  factory Biquad.lowPass(double cutoffHz, double sampleRateHz) {
    final w0 = 2 * math.pi * cutoffHz / sampleRateHz;
    final alpha = math.sin(w0) / (2 * math.sqrt1_2);
    final cosW0 = math.cos(w0);
    final a0 = 1 + alpha;
    return Biquad._(
      (1 - cosW0) / 2 / a0,
      (1 - cosW0) / a0,
      (1 - cosW0) / 2 / a0,
      -2 * cosW0 / a0,
      (1 - alpha) / a0,
    );
  }

  final double _b0, _b1, _b2, _a1, _a2;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  double process(double x) {
    final y = _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }

  void reset() => _x1 = _x2 = _y1 = _y2 = 0;
}

/// Band-pass made of a high-pass and a low-pass in series.
///
/// Earthquake ground motion that a phone can feel sits roughly in 0.5–15 Hz.
/// The high-pass removes gravity and slow tilt; the low-pass removes
/// electrical and fan noise.
class BandPass {
  BandPass({
    required double lowHz,
    required double highHz,
    required double sampleRateHz,
  })  : _hp = Biquad.highPass(lowHz, sampleRateHz),
        _lp = Biquad.lowPass(highHz, sampleRateHz);

  final Biquad _hp;
  final Biquad _lp;

  double process(double x) => _lp.process(_hp.process(x));

  void reset() {
    _hp.reset();
    _lp.reset();
  }
}
