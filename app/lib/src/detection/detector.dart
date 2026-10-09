import 'dart:math' as math;

import 'filters.dart';

/// Tuning knobs for [TremorDetector].
class DetectorConfig {
  const DetectorConfig({
    this.sampleRateHz = 50,
    this.bandLowHz = 0.5,
    this.bandHighHz = 15,
    this.staSeconds = 1,
    this.ltaSeconds = 30,
    this.settleSeconds = 3,
    this.triggerRatio = 4.5,
    this.detriggerRatio = 1.5,
    this.minStaRms = 0.03,
    this.maxNoiseRms = 0.08,
    this.maxPeak = 4.0,
    this.tiltDegrees = 3,
    this.captureSeconds = 2,
    this.minSustainSeconds = 0.8,
    this.cooldownSeconds = 15,
  });

  /// Nominal accelerometer rate. Filters and averaging windows assume it.
  final double sampleRateHz;

  /// Pass band for ground motion, in Hz.
  final double bandLowHz, bandHighHz;

  /// Short-term and long-term averaging windows for the STA/LTA ratio.
  final double staSeconds, ltaSeconds;

  /// Time to let the filters settle after (re)starting before averaging.
  final double settleSeconds;

  /// STA/LTA ratio that starts a capture, and the envelope-to-background
  /// ratio below which a sample doesn't count as shaking.
  final double triggerRatio, detriggerRatio;

  /// Minimum short-term RMS (m/s²) for a trigger. Stops a very quiet phone
  /// from triggering on sensor noise just because the ratio is high.
  final double minStaRms;

  /// Long-term RMS (m/s²) above which the surroundings are too noisy
  /// (washing machine, phone on a bed someone is lying in) to detect anything.
  final double maxNoiseRms;

  /// Peak dynamic acceleration (m/s²) above which the phone was most likely
  /// picked up, knocked or dropped rather than shaken by the ground.
  final double maxPeak;

  /// Orientation change, in degrees, that counts as the phone being moved.
  final double tiltDegrees;

  /// How long to watch after onset before deciding.
  final double captureSeconds;

  /// How long, within the capture window, the shaking envelope must stay
  /// within 10 dB of its peak (and above the background). Rejects single
  /// knocks, footsteps and door slams, which die out in a fraction of a
  /// second.
  final double minSustainSeconds;

  /// Quiet period after a decision before the next trigger is allowed.
  final double cooldownSeconds;

  /// Total time from start until the detector can trigger.
  double get warmupSeconds => settleSeconds + ltaSeconds;

  DetectorConfig copyWith({
    double? triggerRatio,
    double? minStaRms,
    double? sampleRateHz,
  }) =>
      DetectorConfig(
        sampleRateHz: sampleRateHz ?? this.sampleRateHz,
        bandLowHz: bandLowHz,
        bandHighHz: bandHighHz,
        staSeconds: staSeconds,
        ltaSeconds: ltaSeconds,
        settleSeconds: settleSeconds,
        triggerRatio: triggerRatio ?? this.triggerRatio,
        detriggerRatio: detriggerRatio,
        minStaRms: minStaRms ?? this.minStaRms,
        maxNoiseRms: maxNoiseRms,
        maxPeak: maxPeak,
        tiltDegrees: tiltDegrees,
        captureSeconds: captureSeconds,
        minSustainSeconds: minSustainSeconds,
        cooldownSeconds: cooldownSeconds,
      );
}

enum DetectorState {
  /// Filters settling and long-term average filling up.
  warmingUp,

  /// Ready to trigger.
  listening,

  /// Background vibration is too strong to detect anything.
  noisy,

  /// Shaking detected, watching it for [DetectorConfig.captureSeconds].
  capturing,

  /// Just made a decision; ignoring new triggers for a bit.
  cooldown,
}

/// Why a capture was thrown away.
enum RejectReason { impulse, handled }

/// A shaking episode that looked like ground motion.
class Detection {
  const Detection({
    required this.onset,
    required this.peakAccel,
    required this.maxRatio,
    required this.dominantFrequencyHz,
    required this.sustainedSeconds,
    required this.noiseRms,
  });

  /// When the trigger fired.
  final DateTime onset;

  /// Peak band-passed acceleration magnitude, m/s².
  final double peakAccel;

  /// Highest STA/LTA ratio seen during the capture.
  final double maxRatio;

  /// Rough dominant frequency from zero crossings on the strongest axis.
  final double dominantFrequencyHz;

  /// Time the shaking stayed strong during the capture, in seconds.
  final double sustainedSeconds;

  /// Background RMS before the trigger, m/s².
  final double noiseRms;

  @override
  String toString() => 'Detection(onset: $onset, peak: '
      '${peakAccel.toStringAsFixed(3)} m/s², ratio: '
      '${maxRatio.toStringAsFixed(1)}, f: '
      '${dominantFrequencyHz.toStringAsFixed(1)} Hz)';
}

/// Result of feeding one sample to [TremorDetector.add].
sealed class DetectorEvent {
  const DetectorEvent();
}

class Detected extends DetectorEvent {
  const Detected(this.detection);
  final Detection detection;
}

class Rejected extends DetectorEvent {
  const Rejected(this.reason);
  final RejectReason reason;
}

/// Turns a stream of accelerometer samples into tremor detections.
///
/// Pipeline per sample:
///  1. Low-pass the raw vector to track gravity. If the phone's orientation
///     changes by more than [DetectorConfig.tiltDegrees], someone moved it,
///     so the detector restarts.
///  2. Band-pass each axis and take the squared magnitude (energy).
///  3. Classic recursive STA/LTA on that energy. A trigger needs the ratio
///     above [DetectorConfig.triggerRatio] and real amplitude behind it.
///  4. Watch the next couple of seconds: sustained shaking with a plausible
///     peak is reported; short impulses and violent handling are rejected.
class TremorDetector {
  TremorDetector([this.config = const DetectorConfig()]) {
    _buildFilters();
  }

  DetectorConfig config;

  late List<BandPass> _band;
  final List<double> _gravity = [0, 0, 0];
  List<double>? _refGravity;

  int? _startMs;
  double _sta = 0, _lta = 0;
  // Fast (0.1 s) energy envelope, used to judge how long shaking lasts.
  double _env = 0;
  bool _averaging = false;
  int _lastMs = 0;

  DetectorState _state = DetectorState.warmingUp;
  int _cooldownUntilMs = 0;

  // Capture bookkeeping.
  int _onsetMs = 0;
  double _onsetNoise = 0;
  double _peak = 0;
  double _maxRatio = 0;
  final List<double> _envelope = [];
  final List<double> _axisEnergy = [0, 0, 0];
  final List<int> _axisCrossings = [0, 0, 0];
  final List<double> _axisPrev = [0, 0, 0];

  double _lastMagnitude = 0;

  DetectorState get state => _state;

  /// Current STA/LTA ratio (0 while warming up).
  double get ratio => _averaging && _lta > 0 ? _sta / _lta : 0;

  /// Background vibration level, m/s² RMS.
  double get noiseRms => math.sqrt(_lta);

  /// Latest band-passed magnitude, m/s². Handy for drawing a trace.
  double get lastMagnitude => _lastMagnitude;

  /// Seconds left until the detector is ready, or 0.
  double warmupRemaining() {
    if (_state != DetectorState.warmingUp || _startMs == null) return 0;
    final left = config.warmupSeconds * 1000 - (_lastMs - _startMs!);
    return math.max(0, left / 1000);
  }

  /// Applies new settings and starts over.
  void reconfigure(DetectorConfig config) {
    this.config = config;
    reset();
  }

  void reset() {
    _buildFilters();
    _startMs = null;
    _refGravity = null;
    _sta = _lta = 0;
    _averaging = false;
    _state = DetectorState.warmingUp;
  }

  void _buildFilters() {
    _band = List.generate(
      3,
      (_) => BandPass(
        lowHz: config.bandLowHz,
        highHz: config.bandHighHz,
        sampleRateHz: config.sampleRateHz,
      ),
    );
  }

  /// Feeds one accelerometer sample (m/s², including gravity) taken at
  /// [timeMs] (milliseconds since epoch). Returns an event when a capture
  /// finishes, otherwise null.
  DetectorEvent? add(double x, double y, double z, int timeMs) {
    _lastMs = timeMs;
    if (_startMs == null) {
      _startMs = timeMs;
      _gravity
        ..[0] = x
        ..[1] = y
        ..[2] = z;
    }

    _trackGravity(x, y, z);
    if (_refGravity != null && _tiltSinceReference() > config.tiltDegrees) {
      // Moved: everything averaged so far describes a different situation.
      final wasCapturing = _state == DetectorState.capturing;
      reset();
      _startMs = timeMs;
      return wasCapturing ? const Rejected(RejectReason.handled) : null;
    }

    final dx = _band[0].process(x);
    final dy = _band[1].process(y);
    final dz = _band[2].process(z);
    final energy = dx * dx + dy * dy + dz * dz;
    _lastMagnitude = math.sqrt(energy);

    final elapsedS = (timeMs - _startMs!) / 1000;
    if (!_averaging) {
      if (elapsedS < config.settleSeconds) return null;
      _averaging = true;
      _sta = _lta = _env = energy;
      _refGravity = List.of(_gravity);
    }

    final nSta = config.staSeconds * config.sampleRateHz;
    final nLta = config.ltaSeconds * config.sampleRateHz;
    _sta += (energy - _sta) / nSta;
    _env += (energy - _env) / (0.1 * config.sampleRateHz);
    // Freeze the background estimate while shaking so the event doesn't
    // raise its own baseline.
    if (_state != DetectorState.capturing) _lta += (energy - _lta) / nLta;

    final r = ratio;

    switch (_state) {
      case DetectorState.warmingUp:
        if (elapsedS >= config.warmupSeconds) _state = _quietState();
        return null;

      case DetectorState.cooldown:
        if (timeMs >= _cooldownUntilMs) _state = _quietState();
        return null;

      case DetectorState.listening:
      case DetectorState.noisy:
        _state = _quietState();
        if (_state == DetectorState.listening &&
            r >= config.triggerRatio &&
            math.sqrt(_sta) >= config.minStaRms) {
          _beginCapture(timeMs);
          _updateCapture(dx, dy, dz, r);
        }
        return null;

      case DetectorState.capturing:
        _updateCapture(dx, dy, dz, r);
        if (timeMs - _onsetMs < config.captureSeconds * 1000) return null;
        return _finishCapture(timeMs);
    }
  }

  DetectorState _quietState() => math.sqrt(_lta) > config.maxNoiseRms
      ? DetectorState.noisy
      : DetectorState.listening;

  void _trackGravity(double x, double y, double z) {
    // ~1 s time constant.
    final a = 1 / config.sampleRateHz;
    _gravity[0] += (x - _gravity[0]) * a;
    _gravity[1] += (y - _gravity[1]) * a;
    _gravity[2] += (z - _gravity[2]) * a;
  }

  double _tiltSinceReference() {
    final g = _gravity, r = _refGravity!;
    final dot = g[0] * r[0] + g[1] * r[1] + g[2] * r[2];
    final ng = math.sqrt(g[0] * g[0] + g[1] * g[1] + g[2] * g[2]);
    final nr = math.sqrt(r[0] * r[0] + r[1] * r[1] + r[2] * r[2]);
    if (ng == 0 || nr == 0) return 0;
    final c = (dot / (ng * nr)).clamp(-1.0, 1.0);
    return math.acos(c) * 180 / math.pi;
  }

  void _beginCapture(int timeMs) {
    _state = DetectorState.capturing;
    _onsetMs = timeMs;
    _onsetNoise = noiseRms;
    _peak = 0;
    _maxRatio = 0;
    _envelope.clear();
    for (var i = 0; i < 3; i++) {
      _axisEnergy[i] = 0;
      _axisCrossings[i] = 0;
      _axisPrev[i] = 0;
    }
  }

  void _updateCapture(double dx, double dy, double dz, double r) {
    _peak = math.max(_peak, _lastMagnitude);
    _maxRatio = math.max(_maxRatio, r);
    _envelope.add(_env);
    final d = [dx, dy, dz];
    for (var i = 0; i < 3; i++) {
      _axisEnergy[i] += d[i] * d[i];
      if (_axisPrev[i] != 0 && (_axisPrev[i] < 0) != (d[i] < 0)) {
        _axisCrossings[i]++;
      }
      _axisPrev[i] = d[i];
    }
  }

  DetectorEvent _finishCapture(int timeMs) {
    _state = DetectorState.cooldown;
    _cooldownUntilMs = timeMs + (config.cooldownSeconds * 1000).round();

    if (_peak > config.maxPeak) return const Rejected(RejectReason.handled);

    // Samples within 10 dB of the strongest moment and clearly above the
    // background. A knock spikes once and decays; an earthquake keeps going.
    final peakEnv = _envelope.fold(0.0, math.max);
    final floor = math.max(peakEnv * 0.1, _onsetNoise * _onsetNoise * config.detriggerRatio);
    final sustained =
        _envelope.where((e) => e >= floor).length / config.sampleRateHz;
    if (sustained < config.minSustainSeconds) {
      return const Rejected(RejectReason.impulse);
    }

    var strongest = 0;
    for (var i = 1; i < 3; i++) {
      if (_axisEnergy[i] > _axisEnergy[strongest]) strongest = i;
    }
    final durationS = (timeMs - _onsetMs) / 1000;
    final freq = durationS > 0 ? _axisCrossings[strongest] / 2 / durationS : 0.0;

    return Detected(Detection(
      onset: DateTime.fromMillisecondsSinceEpoch(_onsetMs),
      peakAccel: _peak,
      maxRatio: _maxRatio,
      dominantFrequencyHz: freq,
      sustainedSeconds: sustained,
      noiseRms: _onsetNoise,
    ));
  }
}
