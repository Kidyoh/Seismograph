import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:seismograph/src/detection/detector.dart';

const _rate = 50.0;
const _g = 9.81;

/// Feeds [seconds] of samples into [detector] and returns every event.
///
/// [extra] adds dynamic acceleration (x, y, z) at time t (s since start).
/// [tiltDeg] rotates gravity about the x axis by that many degrees at time t.
List<DetectorEvent> run(
  TremorDetector detector,
  double seconds, {
  double noiseRms = 0.005,
  List<double> Function(double t)? extra,
  double Function(double t)? tiltDeg,
  double startS = 0,
  int seed = 1,
}) {
  final rnd = math.Random(seed);
  double noise() {
    // Box–Muller.
    final u = 1 - rnd.nextDouble(), v = rnd.nextDouble();
    return noiseRms * math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }

  final events = <DetectorEvent>[];
  final n = (seconds * _rate).round();
  for (var i = 0; i < n; i++) {
    final t = startS + i / _rate;
    final tilt = (tiltDeg?.call(t) ?? 0) * math.pi / 180;
    final e = extra?.call(t) ?? const [0.0, 0.0, 0.0];
    final ev = detector.add(
      e[0] + noise(),
      _g * math.sin(tilt) + e[1] + noise(),
      _g * math.cos(tilt) + e[2] + noise(),
      (t * 1000).round(),
    );
    if (ev != null) events.add(ev);
  }
  return events;
}

/// A sinusoidal shake on the horizontal axes from [from] for [duration] s.
List<double> Function(double t) shake({
  required double from,
  required double duration,
  required double amp,
  double hz = 3,
}) =>
    (t) {
      if (t < from || t > from + duration) return const [0.0, 0.0, 0.0];
      final s = amp * math.sin(2 * math.pi * hz * (t - from));
      return [s, s * 0.6, s * 0.2];
    };

void main() {
  test('warms up, then listens without false alarms on a quiet table', () {
    final d = TremorDetector();
    expect(run(d, 10), isEmpty);
    expect(d.state, DetectorState.warmingUp);
    expect(run(d, 120, startS: 10), isEmpty);
    expect(d.state, DetectorState.listening);
  });

  test('detects sustained shaking and estimates its frequency', () {
    final d = TremorDetector();
    final events = run(
      d,
      60,
      extra: shake(from: 45, duration: 6, amp: 0.15, hz: 3),
    );
    final detections = events.whereType<Detected>().toList();
    expect(detections, hasLength(1));
    final det = detections.single.detection;
    expect(det.onset.millisecondsSinceEpoch, inInclusiveRange(45000, 46500));
    expect(det.dominantFrequencyHz, closeTo(3, 0.6));
    expect(det.peakAccel, greaterThan(0.1));
    expect(det.sustainedSeconds, greaterThan(1));
  });

  test('ignores shaking during warm-up', () {
    final d = TremorDetector();
    final events = run(d, 30, extra: shake(from: 10, duration: 5, amp: 0.2));
    expect(events.whereType<Detected>(), isEmpty);
  });

  test('rejects a single knock as an impulse', () {
    final d = TremorDetector();
    final events = run(
      d,
      60,
      extra: (t) => (t >= 45 && t < 45.06) ? const [0.0, 0.0, 1.5] : const [0.0, 0.0, 0.0],
    );
    expect(events.whereType<Detected>(), isEmpty);
    expect(
      events.whereType<Rejected>().map((e) => e.reason),
      contains(RejectReason.impulse),
    );
  });

  test('rejects violent movement as handling', () {
    final d = TremorDetector();
    final events = run(d, 60, extra: shake(from: 45, duration: 3, amp: 8));
    expect(events.whereType<Detected>(), isEmpty);
    expect(
      events.whereType<Rejected>().map((e) => e.reason),
      contains(RejectReason.handled),
    );
  });

  test('restarts when the phone is tilted', () {
    final d = TremorDetector();
    run(d, 40);
    expect(d.state, DetectorState.listening);
    run(d, 3, startS: 40, tiltDeg: (t) => (t - 40) * 10);
    expect(d.state, DetectorState.warmingUp);
  });

  test('reports noisy surroundings instead of triggering', () {
    final d = TremorDetector();
    final events = run(d, 90, noiseRms: 0.2);
    expect(events.whereType<Detected>(), isEmpty);
    expect(d.state, DetectorState.noisy);
  });

  test('ignores shaking below the amplitude floor', () {
    final d = TremorDetector();
    final events = run(
      d,
      60,
      noiseRms: 0.001,
      extra: shake(from: 45, duration: 6, amp: 0.01),
    );
    expect(events.whereType<Detected>(), isEmpty);
  });

  test('cools down between detections', () {
    final d = TremorDetector();
    final shakeA = shake(from: 45, duration: 4, amp: 0.15);
    final shakeB = shake(from: 52, duration: 4, amp: 0.15);
    final events = run(
      d,
      70,
      extra: (t) {
        final a = shakeA(t), b = shakeB(t);
        return [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
      },
    );
    expect(events.whereType<Detected>(), hasLength(1));
  });
}
