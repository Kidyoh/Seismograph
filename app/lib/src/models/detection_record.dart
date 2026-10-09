import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../detection/detector.dart';

/// A detection as remembered on this phone.
class DetectionRecord {
  const DetectionRecord({
    required this.onset,
    required this.peakAccel,
    required this.dominantFrequencyHz,
    required this.simulated,
    required this.uploaded,
  });

  factory DetectionRecord.fromDetection(
    Detection d, {
    required bool simulated,
    required bool uploaded,
  }) =>
      DetectionRecord(
        onset: d.onset,
        peakAccel: d.peakAccel,
        dominantFrequencyHz: d.dominantFrequencyHz,
        simulated: simulated,
        uploaded: uploaded,
      );

  factory DetectionRecord.fromJson(Map<String, dynamic> j) => DetectionRecord(
        onset: DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
        peakAccel: (j['peak'] as num).toDouble(),
        dominantFrequencyHz: (j['freq'] as num).toDouble(),
        simulated: j['sim'] as bool? ?? false,
        uploaded: j['up'] as bool? ?? false,
      );

  final DateTime onset;
  final double peakAccel;
  final double dominantFrequencyHz;
  final bool simulated;
  final bool uploaded;

  Map<String, dynamic> toJson() => {
        't': onset.millisecondsSinceEpoch,
        'peak': peakAccel,
        'freq': dominantFrequencyHz,
        'sim': simulated,
        'up': uploaded,
      };
}

/// The most recent detections on this phone, newest first.
class DetectionLog {
  static const _key = 'detectionLog';
  static const _max = 50;

  static Future<List<DetectionRecord>> load() async {
    final raw = await SharedPreferencesAsync().getStringList(_key) ?? const [];
    return [
      for (final s in raw)
        DetectionRecord.fromJson(jsonDecode(s) as Map<String, dynamic>),
    ];
  }

  static Future<void> add(DetectionRecord record) async {
    final p = SharedPreferencesAsync();
    final raw = await p.getStringList(_key) ?? const [];
    await p.setStringList(
      _key,
      [jsonEncode(record.toJson()), ...raw].take(_max).toList(),
    );
  }

  static Future<void> clear() => SharedPreferencesAsync().remove(_key);
}
