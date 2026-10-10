import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../cloud/network.dart';
import '../detection/detector.dart';
import '../models/activity.dart';
import '../models/detection_record.dart';
import '../settings.dart';
import 'status.dart';

/// Nominal accelerometer rate. Earthquake shaking a phone can feel is below
/// ~15 Hz, so 50 Hz is plenty and keeps the CPU mostly idle.
const _sampleRateHz = 50.0;
const _notificationId = 7310;
const _heartbeatEvery = Duration(minutes: 10);

/// Registers the foreground service. Call once from `main`.
Future<void> configureMonitorService() => FlutterBackgroundService().configure(
      androidConfiguration: AndroidConfiguration(
        onStart: monitorServiceMain,
        autoStart: false,
        autoStartOnBoot: true,
        isForegroundMode: true,
        initialNotificationTitle: 'Seismograph',
        initialNotificationContent: 'Starting…',
        foregroundServiceNotificationId: _notificationId,
        foregroundServiceTypes: [AndroidForegroundType.specialUse],
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );

/// Entry point of the background isolate.
@pragma('vm:entry-point')
Future<void> monitorServiceMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  await _Monitor(service).run();
}

/// Runs in the background service. Watches the charger and the clock, and
/// streams the accelerometer into a [TremorDetector] while the gate is open.
class _Monitor {
  _Monitor(this.service);

  final ServiceInstance service;
  final _battery = Battery();
  final _detector = TremorDetector();

  MonitorSettings _settings = const MonitorSettings();
  Network? _network;
  bool _pluggedIn = false;
  GateStatus _gate = GateStatus.disabled;

  StreamSubscription<AccelerometerEvent>? _sensor;
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _ticker;

  DateTime? _listeningSince;

  // Phones don't always honour the requested rate, so measure it once per
  // session and retune the filters if it's far off.
  int? _rateStartMs;
  int _rateSamples = 0;
  bool _rateChecked = false;
  double _rateHz = _sampleRateHz;
  DateTime _lastHeartbeat = DateTime.fromMillisecondsSinceEpoch(0);
  int _detections = 0;
  int _rejected = 0;
  DetectorState? _shownState;

  // The UI pings 'watch' while it is visible; only then do we spend effort
  // sending the live trace.
  DateTime _uiWatchedAt = DateTime.fromMillisecondsSinceEpoch(0);
  final _trace = <double>[];
  DateTime _lastStatusPush = DateTime.fromMillisecondsSinceEpoch(0);

  // Per-minute vibration summary for the "tonight" chart.
  int? _minute;
  double _minuteEnergy = 0;
  double _minutePeak = 0;
  int _minuteSamples = 0;

  // Synthetic shaking for testing the full pipeline.
  int? _simStartMs;
  int _simUntilMs = 0;

  Future<void> run() async {
    _settings = await MonitorSettings.load();
    if (!_settings.enabled) {
      // Started at boot but the user has monitoring off.
      await service.stopSelf();
      return;
    }
    _detector.reconfigure(_detectorConfig);

    _subs
      ..add(service.on('stop').listen((_) => _shutdown()))
      ..add(service.on('reload').listen((_) => _reload()))
      ..add(service.on('watch').listen((_) {
        _uiWatchedAt = DateTime.now();
        _pushStatus(force: true);
      }))
      ..add(service.on('simulate').listen((_) => _simulate()))
      ..add(_battery.onBatteryStateChanged.listen((s) {
        _pluggedIn = _isPluggedIn(s);
        _evaluate();
      }));

    _pluggedIn = _isPluggedIn(await _battery.batteryState);
    if (_settings.shareWithNetwork) _network = await Network.connect();

    // Re-check the night window and send heartbeats.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => _evaluate());
    _evaluate();
  }

  DetectorConfig get _detectorConfig => _settings.sensitivity
      .apply(const DetectorConfig().copyWith(sampleRateHz: _rateHz));

  static bool _isPluggedIn(BatteryState s) =>
      s == BatteryState.charging ||
      s == BatteryState.full ||
      s == BatteryState.connectedNotCharging;

  Future<void> _reload() async {
    final old = _settings;
    _settings = await MonitorSettings.load();
    if (!_settings.enabled) return _shutdown();
    if (_settings.sensitivity != old.sensitivity) {
      _detector.reconfigure(_detectorConfig);
    }
    if (_settings.shareWithNetwork && _network == null) {
      _network = await Network.connect();
    } else if (!_settings.shareWithNetwork && _network != null) {
      await _sendHeartbeat(listening: false);
      _network = null;
    }
    _evaluate();
  }

  void _evaluate() {
    _gate = evaluateGate(
      settings: _settings,
      pluggedIn: _pluggedIn,
      now: DateTime.now(),
    );
    final shouldListen = _gate == GateStatus.open;

    if (shouldListen && _sensor == null) {
      _startListening();
    } else if (!shouldListen && _sensor != null) {
      _stopListening();
    }

    if (_sensor != null &&
        DateTime.now().difference(_lastHeartbeat) >= _heartbeatEvery) {
      _sendHeartbeat(listening: true);
    }
    _updateNotification();
    _pushStatus(force: true);
  }

  void _startListening() {
    _rateHz = _sampleRateHz;
    _detector.reconfigure(_detectorConfig);
    _rateStartMs = null;
    _rateSamples = 0;
    _rateChecked = false;
    _listeningSince = DateTime.now();
    _detections = 0;
    _rejected = 0;
    _sensor = accelerometerEventStream(
      samplingPeriod: Duration(microseconds: 1e6 ~/ _sampleRateHz),
    ).listen(_onSample, onError: (Object e) => debugPrint('Sensor error: $e'));
    _sendHeartbeat(listening: true);
  }

  void _stopListening() {
    _flushMinute();
    _sensor?.cancel();
    _sensor = null;
    _listeningSince = null;
    _sendHeartbeat(listening: false);
  }

  void _onSample(AccelerometerEvent e) {
    final t = e.timestamp.millisecondsSinceEpoch;
    if (!_rateChecked) _measureRate(t);
    var x = e.x, y = e.y;
    if (_simStartMs != null) {
      final s = _syntheticShake(t);
      x += s;
      y += s * 0.6;
    }

    final event = _detector.add(x, y, e.z, t);
    switch (event) {
      case Detected(:final detection):
        _onDetection(detection);
      case Rejected():
        _rejected++;
      case null:
        break;
    }

    _recordActivity(t);

    if (_detector.state != _shownState) {
      _shownState = _detector.state;
      _updateNotification();
    }

    if (_uiIsWatching) {
      _trace.add(_detector.lastMagnitude);
      if (_trace.length >= 10) {
        service.invoke('trace', {'v': List.of(_trace)});
        _trace.clear();
      }
      _pushStatus();
    }
  }

  void _measureRate(int t) {
    _rateStartMs ??= t;
    _rateSamples++;
    final elapsed = (t - _rateStartMs!) / 1000;
    if (elapsed < 10) return;
    _rateChecked = true;
    final measured = _rateSamples / elapsed;
    if ((measured - _sampleRateHz).abs() / _sampleRateHz > 0.2) {
      debugPrint('Accelerometer runs at ${measured.toStringAsFixed(1)} Hz');
      _rateHz = measured;
      _detector.reconfigure(_detectorConfig);
    }
  }

  void _recordActivity(int t) {
    // Skip calibration: the filters are still settling.
    if (_detector.state == DetectorState.warmingUp) return;
    final minute = t ~/ 60000;
    if (_minute != null && minute != _minute) _flushMinute();
    _minute = minute;
    final m = _detector.lastMagnitude;
    _minuteEnergy += m * m;
    _minutePeak = math.max(_minutePeak, m);
    _minuteSamples++;
  }

  void _flushMinute() {
    final minute = _minute;
    if (minute != null && _minuteSamples > 0) {
      final point = ActivityPoint(
        DateTime.fromMillisecondsSinceEpoch(minute * 60000),
        math.sqrt(_minuteEnergy / _minuteSamples),
        _minutePeak,
      );
      ActivityLog.add(point);
      service.invoke('activity', point.toJson());
    }
    _minute = null;
    _minuteEnergy = _minutePeak = 0;
    _minuteSamples = 0;
  }

  bool get _uiIsWatching =>
      DateTime.now().difference(_uiWatchedAt) < const Duration(seconds: 5);

  /// About 5 s of 3 Hz shaking at 0.15 m/s², similar to light earthquake
  /// shaking (MMI IV) on a nightstand.
  double _syntheticShake(int t) {
    if (t > _simUntilMs) {
      _simStartMs = null;
      return 0;
    }
    final dt = (t - _simStartMs!) / 1000;
    final envelope = math.min(1.0, dt / 0.5) * math.min(1.0, (_simUntilMs - t) / 500);
    return 0.15 * envelope * math.sin(2 * math.pi * 3 * dt);
  }

  void _simulate() {
    if (_sensor == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _simStartMs = now;
    _simUntilMs = now + 5000;
  }

  Future<void> _onDetection(Detection d) async {
    _detections++;
    // A detection that starts while synthetic shaking is on is a test.
    final simulated = _simStartMs != null ||
        d.onset.millisecondsSinceEpoch <= _simUntilMs;
    var uploaded = false;
    final net = _network;
    if (net != null && _settings.hasLocation) {
      try {
        await net.reportDetection(
          d,
          lat: _settings.latitude!,
          lng: _settings.longitude!,
          simulated: simulated,
        );
        uploaded = true;
      } catch (e) {
        debugPrint('Upload failed: $e');
      }
    }
    final record = DetectionRecord.fromDetection(
      d,
      simulated: simulated,
      uploaded: uploaded,
    );
    await DetectionLog.add(record);
    service.invoke('detection', record.toJson());
    _updateNotification();
  }

  Future<void> _sendHeartbeat({required bool listening}) async {
    final net = _network;
    if (net == null || !_settings.hasLocation) return;
    _lastHeartbeat = DateTime.now();
    try {
      await net.heartbeat(
        lat: _settings.latitude!,
        lng: _settings.longitude!,
        listening: listening,
      );
    } catch (e) {
      debugPrint('Heartbeat failed: $e');
    }
  }

  void _updateNotification() {
    final s = service;
    if (s is! AndroidServiceInstance) return;
    final String content;
    if (_sensor == null) {
      content = _gate.label;
    } else {
      content = switch (_detector.state) {
        DetectorState.warmingUp => 'Calibrating…',
        DetectorState.noisy => 'Too much vibration nearby',
        DetectorState.capturing => 'Shaking detected…',
        _ => _detections == 0
            ? 'Listening for tremors'
            : 'Listening · $_detections detection${_detections == 1 ? '' : 's'} tonight',
      };
    }
    s.setForegroundNotificationInfo(title: 'Seismograph', content: content);
  }

  void _pushStatus({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastStatusPush) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastStatusPush = now;
    service.invoke(
      'status',
      MonitorStatus(
        gate: _gate,
        pluggedIn: _pluggedIn,
        listening: _sensor != null,
        detectorState: _sensor == null ? null : _detector.state,
        ratio: _detector.ratio,
        noiseRms: _detector.noiseRms,
        warmupRemaining: _detector.warmupRemaining(),
        listeningSince: _listeningSince,
        detections: _detections,
        rejected: _rejected,
        networkConnected: _network != null,
        hasLocation: _settings.hasLocation,
      ).toJson(),
    );
  }

  Future<void> _shutdown() async {
    _ticker?.cancel();
    if (_sensor != null) _stopListening();
    for (final s in _subs) {
      await s.cancel();
    }
    service.invoke('status', MonitorStatus.stopped.toJson());
    await service.stopSelf();
  }
}
