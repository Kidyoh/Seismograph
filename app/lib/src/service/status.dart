import '../detection/detector.dart';
import '../settings.dart';

/// Snapshot of the background service, sent to the UI.
class MonitorStatus {
  const MonitorStatus({
    required this.gate,
    required this.pluggedIn,
    required this.listening,
    required this.detectorState,
    required this.ratio,
    required this.noiseRms,
    required this.warmupRemaining,
    required this.listeningSince,
    required this.detections,
    required this.rejected,
    required this.networkConnected,
    required this.hasLocation,
  });

  static const stopped = MonitorStatus(
    gate: GateStatus.disabled,
    pluggedIn: false,
    listening: false,
    detectorState: null,
    ratio: 0,
    noiseRms: 0,
    warmupRemaining: 0,
    listeningSince: null,
    detections: 0,
    rejected: 0,
    networkConnected: false,
    hasLocation: false,
  );

  factory MonitorStatus.fromJson(Map<String, dynamic> j) {
    final since = j['since'] as int?;
    final state = j['state'] as String?;
    return MonitorStatus(
      gate: GateStatus.values.byName(j['gate'] as String),
      pluggedIn: j['plugged'] as bool,
      listening: j['listening'] as bool,
      detectorState: state == null ? null : DetectorState.values.byName(state),
      ratio: (j['ratio'] as num).toDouble(),
      noiseRms: (j['noise'] as num).toDouble(),
      warmupRemaining: (j['warmup'] as num).toDouble(),
      listeningSince:
          since == null ? null : DateTime.fromMillisecondsSinceEpoch(since),
      detections: j['detections'] as int,
      rejected: j['rejected'] as int,
      networkConnected: j['network'] as bool,
      hasLocation: j['location'] as bool,
    );
  }

  final GateStatus gate;
  final bool pluggedIn;
  final bool listening;
  final DetectorState? detectorState;
  final double ratio;
  final double noiseRms;
  final double warmupRemaining;
  final DateTime? listeningSince;
  final int detections;
  final int rejected;
  final bool networkConnected;
  final bool hasLocation;

  Map<String, dynamic> toJson() => {
        'gate': gate.name,
        'plugged': pluggedIn,
        'listening': listening,
        'state': detectorState?.name,
        'ratio': ratio.isFinite ? ratio : 0,
        'noise': noiseRms.isFinite ? noiseRms : 0,
        'warmup': warmupRemaining,
        'since': listeningSince?.millisecondsSinceEpoch,
        'detections': detections,
        'rejected': rejected,
        'network': networkConnected,
        'location': hasLocation,
      };
}
