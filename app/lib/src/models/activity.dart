import 'package:shared_preferences/shared_preferences.dart';

/// Vibration summary for one minute of listening.
class ActivityPoint {
  const ActivityPoint(this.time, this.rms, this.peak);

  factory ActivityPoint.fromJson(Map<String, dynamic> j) => ActivityPoint(
        DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
        (j['rms'] as num).toDouble(),
        (j['peak'] as num).toDouble(),
      );

  factory ActivityPoint._decode(String s) {
    final p = s.split(',');
    return ActivityPoint(
      DateTime.fromMillisecondsSinceEpoch(int.parse(p[0])),
      double.parse(p[1]),
      double.parse(p[2]),
    );
  }

  /// Start of the minute.
  final DateTime time;

  /// RMS of the band-passed acceleration over the minute, m/s².
  final double rms;

  /// Strongest moment in the minute, m/s².
  final double peak;

  Map<String, dynamic> toJson() => {'t': time.millisecondsSinceEpoch, 'rms': rms, 'peak': peak};

  String _encode() =>
      '${time.millisecondsSinceEpoch},${rms.toStringAsFixed(5)},${peak.toStringAsFixed(5)}';
}

/// The last night of per-minute vibration levels.
class ActivityLog {
  static const _key = 'activityLog';

  /// Long enough for any night, short enough that last night is gone by
  /// the next evening.
  static const keep = Duration(hours: 14);

  static Future<List<ActivityPoint>> load() async {
    final raw = await SharedPreferencesAsync().getStringList(_key) ?? const [];
    return prune([for (final s in raw) ActivityPoint._decode(s)]);
  }

  static Future<void> add(ActivityPoint point) async {
    final p = SharedPreferencesAsync();
    final raw = await p.getStringList(_key) ?? const [];
    final points = prune([...raw.map(ActivityPoint._decode), point]);
    await p.setStringList(_key, [for (final x in points) x._encode()]);
  }

  static List<ActivityPoint> prune(List<ActivityPoint> points) {
    final cutoff = DateTime.now().subtract(keep);
    return [for (final x in points) if (x.time.isAfter(cutoff)) x];
  }

  static Future<void> clear() => SharedPreferencesAsync().remove(_key);
}
