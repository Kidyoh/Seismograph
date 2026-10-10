import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../cloud/network.dart';
import '../geo.dart';
import '../models/activity.dart';
import '../models/detection_record.dart';
import '../models/quake_event.dart';
import '../service/status.dart';
import '../settings.dart';

/// UI-side state: settings, the background service's status, the live trace
/// and this phone's detection history.
class MonitorController extends ChangeNotifier {
  final _service = FlutterBackgroundService();
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _watchTimer;
  AppLifecycleListener? _lifecycle;

  MonitorSettings settings = const MonitorSettings();
  MonitorStatus status = MonitorStatus.stopped;
  List<DetectionRecord> history = const [];

  /// Per-minute vibration for the last night.
  List<ActivityPoint> activity = const [];

  /// Last ten seconds of band-passed acceleration magnitude.
  final trace = TraceBuffer(500);

  /// Null until we know; false when the app was built without Firebase.
  bool? networkAvailable;

  /// Confirmed events from the network, newest first. Null until loaded.
  List<QuakeEvent>? events;
  Object? eventsError;

  Future<void> init() async {
    settings = await MonitorSettings.load();
    history = await DetectionLog.load();
    activity = await ActivityLog.load();
    notifyListeners();

    _subs
      ..add(_service.on('status').listen((j) {
        if (j == null) return;
        status = MonitorStatus.fromJson(j);
        notifyListeners();
      }))
      ..add(_service.on('trace').listen((j) {
        for (final v in (j?['v'] as List? ?? const [])) {
          trace.add((v as num).toDouble());
        }
        notifyListeners();
      }))
      ..add(_service.on('activity').listen((j) {
        if (j == null) return;
        activity = ActivityLog.prune([...activity, ActivityPoint.fromJson(j)]);
        notifyListeners();
      }))
      ..add(_service.on('detection').listen((j) async {
        history = await DetectionLog.load();
        notifyListeners();
      }));

    _lifecycle = AppLifecycleListener(
      onResume: _startWatching,
      onPause: _stopWatching,
    );
    _startWatching();

    if (settings.enabled && !await _service.isRunning()) {
      await _service.startService();
    }

    final net = await Network.connect();
    networkAvailable = net != null;
    if (net != null) {
      _subs.add(Network.recentEvents().listen(
        (e) {
          events = e;
          eventsError = null;
          notifyListeners();
        },
        onError: (Object e) {
          eventsError = e;
          notifyListeners();
        },
      ));
    }
    notifyListeners();
  }

  void _startWatching() {
    _watchTimer?.cancel();
    _service.invoke('watch');
    _watchTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _service.invoke('watch'),
    );
  }

  void _stopWatching() {
    _watchTimer?.cancel();
    _watchTimer = null;
  }

  /// Turns monitoring on or off. Returns a message for the user when
  /// something needs their attention.
  Future<String?> setEnabled(bool enabled) async {
    String? warning;
    if (enabled) {
      // The ongoing notification needs this on Android 13+. Monitoring still
      // works without it, the notification just stays hidden.
      await Permission.notification.request();
      if (!settings.hasLocation) {
        warning = await refreshLocation();
        if (warning != null) {
          warning = '$warning Detections will stay on this phone until a '
              'location is set.';
        }
      }
    }

    settings = settings.copyWith(enabled: enabled);
    await settings.save();
    notifyListeners();

    if (enabled) {
      if (await _service.isRunning()) {
        _service.invoke('reload');
      } else {
        await _service.startService();
      }
    } else {
      _service.invoke('stop');
      status = MonitorStatus.stopped;
      trace.clear();
    }
    notifyListeners();
    return warning;
  }

  Future<void> update(MonitorSettings next) async {
    settings = next;
    await settings.save();
    notifyListeners();
    _service.invoke('reload');
  }

  /// Asks for coarse location once and stores it rounded to ~1 km. Returns
  /// an error message, or null on success.
  Future<String?> refreshLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Location services are off.';
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return 'Location permission was not granted.';
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 30),
        ),
      );
      await update(settings.copyWith(
        latitude: coarsen(pos.latitude),
        longitude: coarsen(pos.longitude),
      ));
      return null;
    } catch (e) {
      return 'Could not get a location fix.';
    }
  }

  void simulate() => _service.invoke('simulate');

  Future<void> clearHistory() async {
    await DetectionLog.clear();
    await ActivityLog.clear();
    history = const [];
    activity = const [];
    notifyListeners();
  }

  @override
  void dispose() {
    _stopWatching();
    _lifecycle?.dispose();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

/// Fixed-size ring buffer for the live trace.
class TraceBuffer {
  TraceBuffer(this.capacity) : _data = List.filled(capacity, 0);

  final int capacity;
  final List<double> _data;
  int _next = 0;
  int _length = 0;
  int _total = 0;

  int get length => _length;

  /// Values added since creation. Changes on every [add].
  int get total => _total;

  void add(double v) {
    _total++;
    _data[_next] = v;
    _next = (_next + 1) % capacity;
    if (_length < capacity) _length++;
  }

  void clear() => _next = _length = 0;

  /// Oldest to newest.
  double operator [](int i) =>
      _data[(_next - _length + i + capacity) % capacity];
}
