import 'package:flutter/material.dart';

import '../detection/detector.dart';
import '../geo.dart';
import '../models/detection_record.dart';
import '../models/quake_event.dart';
import '../service/status.dart';
import '../settings.dart';
import 'monitor_controller.dart';
import 'settings_page.dart';
import 'trace_view.dart';

/// Only show confirmed events this close to home.
const _nearbyKm = 300.0;

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});

  final MonitorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Seismograph'),
          actions: [
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.tune),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => SettingsPage(controller: controller),
              )),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _StatusCard(controller: controller),
            if (controller.status.listening) ...[
              const SizedBox(height: 12),
              _TraceCard(controller: controller),
            ],
            const SizedBox(height: 24),
            _SectionTitle('Confirmed near you'),
            _NetworkEvents(controller: controller),
            const SizedBox(height: 24),
            _SectionTitle('This phone'),
            _LocalHistory(history: controller.history),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});

  final MonitorController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.status;
    final settings = controller.settings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (icon, title, color) = _headline(s, settings, scheme);
    final details = <String>[
      if (settings.enabled) s.pluggedIn ? 'Plugged in' : 'On battery',
      if (s.listening && s.detectorState != DetectorState.warmingUp)
        'Background ${s.noiseRms.toStringAsFixed(3)} m/s²',
      if (settings.enabled && settings.shareWithNetwork)
        !s.hasLocation
            ? 'No location set'
            : s.networkConnected
                ? 'Sharing with network'
                : 'Network offline',
      if (s.listening && s.detections > 0)
        '${s.detections} detection${s.detections == 1 ? '' : 's'} tonight',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 40, color: color),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleLarge),
                      if (details.isNotEmpty)
                        Text(
                          details.join(' · '),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Overnight monitoring'),
              subtitle: Text(
                settings.nightOnly
                    ? 'Listens while charging, '
                        '${_hour(settings.startHour)}–${_hour(settings.endHour)}'
                    : 'Listens whenever the phone is charging',
              ),
              value: settings.enabled,
              onChanged: (v) async {
                final warning = await controller.setEnabled(v);
                if (warning != null && context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(warning)));
                }
              },
            ),
            if (settings.enabled && s.listening)
              Text(
                'Leave the phone flat on a nightstand or table, not on the bed.',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  (IconData, String, Color) _headline(
    MonitorStatus s,
    MonitorSettings settings,
    ColorScheme scheme,
  ) {
    if (!settings.enabled) {
      return (Icons.sensors_off, 'Monitoring off', scheme.outline);
    }
    if (!s.listening) {
      return switch (s.gate) {
        GateStatus.notCharging => (Icons.power_off, 'Waiting for charger', scheme.outline),
        GateStatus.outsideHours => (Icons.bedtime_outlined, 'Waiting for night', scheme.outline),
        _ => (Icons.hourglass_empty, 'Starting…', scheme.outline),
      };
    }
    return switch (s.detectorState) {
      DetectorState.warmingUp => (
          Icons.tune,
          'Calibrating · ${s.warmupRemaining.ceil()}s',
          scheme.tertiary,
        ),
      DetectorState.noisy => (Icons.vibration, 'Too much vibration', scheme.error),
      DetectorState.capturing => (Icons.waves, 'Shaking detected', scheme.error),
      _ => (Icons.sensors, 'Listening', scheme.primary),
    };
  }
}

class _TraceCard extends StatelessWidget {
  const _TraceCard({required this.controller});

  final MonitorController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.status;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 120, child: TraceView(trace: controller.trace)),
            const SizedBox(height: 4),
            Text(
              'Last 10 s · STA/LTA ${s.ratio.toStringAsFixed(1)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkEvents extends StatelessWidget {
  const _NetworkEvents({required this.controller});

  final MonitorController controller;

  @override
  Widget build(BuildContext context) {
    final available = controller.networkAvailable;
    if (available == null) {
      return const Card(child: ListTile(title: Text('Connecting…')));
    }
    if (!available) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.cloud_off),
          title: Text('Network not configured'),
          subtitle: Text(
            'This build has no Firebase project. Detections stay on this '
            'phone. See the README to connect one.',
          ),
        ),
      );
    }
    final settings = controller.settings;
    return StreamBuilder<List<QuakeEvent>>(
      stream: controller.events,
      builder: (context, snap) {
        if (snap.hasError) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Could not load events'),
              subtitle: Text('${snap.error}'),
            ),
          );
        }
        if (!snap.hasData) {
          return const Card(child: ListTile(title: Text('Loading…')));
        }
        final events = [
          for (final e in snap.data!)
            if (!settings.hasLocation ||
                distanceKm(settings.latitude!, settings.longitude!,
                        e.latitude, e.longitude) <=
                    _nearbyKm)
              e,
        ];
        if (events.isEmpty) {
          return const Card(
            child: ListTile(
              leading: Icon(Icons.check_circle_outline),
              title: Text('No tremors in the last 7 days'),
            ),
          );
        }
        return Card(
          child: Column(
            children: [
              for (final e in events) _EventTile(event: e, settings: settings),
            ],
          ),
        );
      },
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.settings});

  final QuakeEvent event;
  final MonitorSettings settings;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final scheme = Theme.of(context).colorScheme;
    final parts = [
      _when(e.time),
      e.activeCount > 0
          ? '${e.deviceCount} of ${e.activeCount} phones'
          : '${e.deviceCount} phones',
      if (settings.hasLocation)
        '${distanceKm(settings.latitude!, settings.longitude!, e.latitude, e.longitude).round()} km away',
    ];
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: e.mmi >= 5 ? scheme.errorContainer : scheme.primaryContainer,
        child: Text(e.mmi.toStringAsFixed(0)),
      ),
      title: Row(
        children: [
          Flexible(child: Text('${describeMmi(e.mmi)} shaking')),
          if (e.test) ...[
            const SizedBox(width: 8),
            const _Tag('TEST'),
          ],
        ],
      ),
      subtitle: Text(parts.join(' · ')),
    );
  }
}

class _LocalHistory extends StatelessWidget {
  const _LocalHistory({required this.history});

  final List<DetectionRecord> history;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.nights_stay_outlined),
          title: Text('Nothing detected yet'),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          for (final r in history.take(10))
            ListTile(
              dense: true,
              leading: Icon(r.uploaded ? Icons.cloud_done_outlined : Icons.phone_android),
              title: Row(
                children: [
                  Text(_when(r.onset)),
                  if (r.simulated) ...[
                    const SizedBox(width: 8),
                    const _Tag('TEST'),
                  ],
                ],
              ),
              subtitle: Text(
                'Peak ${r.peakAccel.toStringAsFixed(3)} m/s² · '
                '${r.dominantFrequencyHz.toStringAsFixed(1)} Hz',
              ),
            ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: scheme.onSecondaryContainer),
      ),
    );
  }
}

String _hour(int h) => '${h.toString().padLeft(2, '0')}:00';

String _when(DateTime t) {
  final now = DateTime.now();
  final hm = '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final daysAgo = today.difference(day).inDays;
  if (daysAgo == 0) return 'Today $hm';
  if (daysAgo == 1) return 'Yesterday $hm';
  return '${t.day}/${t.month} $hm';
}
