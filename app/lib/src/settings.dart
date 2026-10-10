import 'package:shared_preferences/shared_preferences.dart';

import 'detection/detector.dart';

enum Sensitivity {
  low(triggerRatio: 6, minStaRms: 0.05),
  medium(triggerRatio: 4.5, minStaRms: 0.03),
  high(triggerRatio: 3.5, minStaRms: 0.015);

  const Sensitivity({required this.triggerRatio, required this.minStaRms});

  final double triggerRatio;
  final double minStaRms;

  DetectorConfig apply(DetectorConfig base) =>
      base.copyWith(triggerRatio: triggerRatio, minStaRms: minStaRms);
}

/// User settings, shared between the UI and the background service.
///
/// Stored with [SharedPreferencesAsync], which never caches, so both isolates
/// always see the latest values.
class MonitorSettings {
  const MonitorSettings({
    this.enabled = false,
    this.sensitivity = Sensitivity.medium,
    this.nightOnly = true,
    this.requireCharger = true,
    this.startHour = 22,
    this.endHour = 7,
    this.shareWithNetwork = true,
    this.latitude,
    this.longitude,
  });

  /// Master switch: monitor whenever the phone is charging (and, if
  /// [nightOnly], within the night window).
  final bool enabled;
  final Sensitivity sensitivity;
  final bool nightOnly;

  /// Only listen while plugged in. When false the app also listens on
  /// battery, down to [minBatteryPercent].
  final bool requireCharger;

  /// Night window in local hours, [startHour] inclusive to [endHour]
  /// exclusive. May wrap past midnight.
  final int startHour, endHour;

  /// Upload detections and heartbeats so the network can confirm quakes.
  final bool shareWithNetwork;

  /// Coarse home location, already rounded to about 1 km.
  final double? latitude, longitude;

  bool get hasLocation => latitude != null && longitude != null;

  MonitorSettings copyWith({
    bool? enabled,
    Sensitivity? sensitivity,
    bool? nightOnly,
    bool? requireCharger,
    int? startHour,
    int? endHour,
    bool? shareWithNetwork,
    double? latitude,
    double? longitude,
  }) =>
      MonitorSettings(
        enabled: enabled ?? this.enabled,
        sensitivity: sensitivity ?? this.sensitivity,
        nightOnly: nightOnly ?? this.nightOnly,
        requireCharger: requireCharger ?? this.requireCharger,
        startHour: startHour ?? this.startHour,
        endHour: endHour ?? this.endHour,
        shareWithNetwork: shareWithNetwork ?? this.shareWithNetwork,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
      );

  static const _kEnabled = 'enabled';
  static const _kSensitivity = 'sensitivity';
  static const _kNightOnly = 'nightOnly';
  static const _kRequireCharger = 'requireCharger';
  static const _kStartHour = 'startHour';
  static const _kEndHour = 'endHour';
  static const _kShare = 'shareWithNetwork';
  static const _kLat = 'latitude';
  static const _kLng = 'longitude';

  static Future<MonitorSettings> load() async {
    final p = SharedPreferencesAsync();
    const d = MonitorSettings();
    final sensitivityName = await p.getString(_kSensitivity);
    return MonitorSettings(
      enabled: await p.getBool(_kEnabled) ?? d.enabled,
      sensitivity: Sensitivity.values.firstWhere(
        (s) => s.name == sensitivityName,
        orElse: () => d.sensitivity,
      ),
      nightOnly: await p.getBool(_kNightOnly) ?? d.nightOnly,
      requireCharger: await p.getBool(_kRequireCharger) ?? d.requireCharger,
      startHour: await p.getInt(_kStartHour) ?? d.startHour,
      endHour: await p.getInt(_kEndHour) ?? d.endHour,
      shareWithNetwork: await p.getBool(_kShare) ?? d.shareWithNetwork,
      latitude: await p.getDouble(_kLat),
      longitude: await p.getDouble(_kLng),
    );
  }

  Future<void> save() async {
    final p = SharedPreferencesAsync();
    await p.setBool(_kEnabled, enabled);
    await p.setString(_kSensitivity, sensitivity.name);
    await p.setBool(_kNightOnly, nightOnly);
    await p.setBool(_kRequireCharger, requireCharger);
    await p.setInt(_kStartHour, startHour);
    await p.setInt(_kEndHour, endHour);
    await p.setBool(_kShare, shareWithNetwork);
    if (hasLocation) {
      await p.setDouble(_kLat, latitude!);
      await p.setDouble(_kLng, longitude!);
    }
  }
}

/// Why the service is or isn't listening right now.
enum GateStatus {
  disabled('Monitoring is off'),
  notCharging('Waiting for charger'),
  lowBattery('Paused: battery low'),
  outsideHours('Waiting for night window'),
  open('Listening');

  const GateStatus(this.label);
  final String label;
}

/// On battery, stop listening below this charge so the phone still has
/// plenty left in the morning.
const minBatteryPercent = 20;

/// Decides whether the accelerometer should run.
GateStatus evaluateGate({
  required MonitorSettings settings,
  required bool pluggedIn,
  required DateTime now,
  int batteryPercent = 100,
}) {
  if (!settings.enabled) return GateStatus.disabled;
  if (!pluggedIn) {
    if (settings.requireCharger) return GateStatus.notCharging;
    if (batteryPercent < minBatteryPercent) return GateStatus.lowBattery;
  }
  if (settings.nightOnly &&
      !isWithinHours(now.hour, settings.startHour, settings.endHour)) {
    return GateStatus.outsideHours;
  }
  return GateStatus.open;
}

/// Whether [hour] falls in [start, end), wrapping past midnight when
/// start > end. Equal start and end means all day.
bool isWithinHours(int hour, int start, int end) {
  if (start == end) return true;
  if (start < end) return hour >= start && hour < end;
  return hour >= start || hour < end;
}
