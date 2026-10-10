import 'package:flutter/material.dart';

import '../detection/detector.dart';
import '../geo.dart';
import '../models/detection_record.dart';
import '../models/quake_event.dart';
import '../service/status.dart';
import '../settings.dart';
import 'monitor_controller.dart';
import 'pulse_dot.dart';
import 'settings_page.dart';
import 'theme.dart';
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
      builder: (context, _) {
        final view = _StatusView.of(controller.status, controller.settings);
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                _Header(controller: controller),
                const SizedBox(height: 20),
                _Hero(view: view, status: controller.status),
                const SizedBox(height: 20),
                _TracePanel(controller: controller, view: view),
                const SizedBox(height: 12),
                _Readouts(status: controller.status),
                const SizedBox(height: 16),
                _Conditions(controller: controller),
                const SizedBox(height: 16),
                _MonitoringToggle(controller: controller),
                const SizedBox(height: 32),
                const _SectionLabel('CONFIRMED NEAR YOU'),
                _NetworkEvents(controller: controller),
                const SizedBox(height: 32),
                const _SectionLabel('THIS PHONE'),
                _LocalHistory(history: controller.history),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// What to show for the current state, in one place.
class _StatusView {
  const _StatusView(this.title, this.subtitle, this.color, {this.pulsing = false, this.idleHint});

  factory _StatusView.of(MonitorStatus s, MonitorSettings settings) {
    if (!settings.enabled) {
      return const _StatusView(
        'Off',
        'Turn on overnight monitoring below',
        Palette.faint,
        idleHint: 'Monitoring is off',
      );
    }
    if (!s.listening) {
      return switch (s.gate) {
        GateStatus.notCharging => const _StatusView(
            'Waiting',
            'Plug in the phone to start listening',
            Palette.muted,
            idleHint: 'Plug in to start',
          ),
        GateStatus.outsideHours => _StatusView(
            'Resting',
            'Starts at ${_hour(settings.startHour)} while charging',
            Palette.muted,
            idleHint: 'Back at ${_hour(settings.startHour)}',
          ),
        _ => const _StatusView('Starting', 'Waking the sensor…', Palette.muted, idleHint: '…'),
      };
    }
    return switch (s.detectorState) {
      DetectorState.warmingUp => const _StatusView(
          'Calibrating',
          'Learning how still this spot is',
          Palette.teal,
          pulsing: true,
        ),
      DetectorState.noisy => const _StatusView(
          'Too noisy',
          'Something nearby keeps vibrating. Try a firmer surface.',
          Palette.red,
        ),
      DetectorState.capturing => const _StatusView(
          'Shaking',
          'Checking whether it looks like a tremor…',
          Palette.red,
          pulsing: true,
        ),
      _ => const _StatusView(
          'Listening',
          'Feeling for tremors. Sleep well.',
          Palette.amber,
          pulsing: true,
        ),
    };
  }

  final String title;
  final String subtitle;
  final Color color;
  final bool pulsing;

  /// Message over the empty trace when the sensor is off.
  final String? idleHint;
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final MonitorController controller;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text('SEISMOGRAPH', style: labelStyle.copyWith(fontSize: 13, letterSpacing: 3, color: Palette.text)),
          const Spacer(),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune_rounded, color: Palette.muted),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => SettingsPage(controller: controller),
            )),
          ),
        ],
      );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.view, required this.status});

  final _StatusView view;
  final MonitorStatus status;

  @override
  Widget build(BuildContext context) {
    final warming = status.listening && status.detectorState == DetectorState.warmingUp;
    final total = const DetectorConfig().warmupSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PulseDot(color: view.color, pulsing: view.pulsing),
            const SizedBox(width: 14),
            Text(
              view.title,
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w500, height: 1.1, letterSpacing: -0.5),
            ),
            if (warming) ...[
              const Spacer(),
              Text('${status.warmupRemaining.ceil()} s', style: readoutStyle.copyWith(color: Palette.teal)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 30),
          child: Text(view.subtitle, style: const TextStyle(fontSize: 15, color: Palette.muted)),
        ),
        if (warming) ...[
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: (1 - status.warmupRemaining / total).clamp(0.0, 1.0),
              minHeight: 3,
              color: Palette.teal,
              backgroundColor: Palette.surfaceHigh,
            ),
          ),
        ],
      ],
    );
  }
}

class _TracePanel extends StatelessWidget {
  const _TracePanel({required this.controller, required this.view});

  final MonitorController controller;
  final _StatusView view;

  @override
  Widget build(BuildContext context) {
    final listening = controller.status.listening;
    final shaking = controller.status.detectorState == DetectorState.capturing;
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Palette.outline),
        boxShadow: listening
            ? [BoxShadow(color: view.color.withValues(alpha: 0.08), blurRadius: 40, spreadRadius: 2)]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: TraceView(
              trace: controller.trace,
              active: listening,
              color: shaking ? Palette.red : Palette.amber,
            ),
          ),
          if (!listening && view.idleHint != null)
            Center(
              child: Text(view.idleHint!, style: labelStyle.copyWith(fontSize: 12, color: Palette.faint)),
            ),
          const Positioned(
            left: 12,
            bottom: 8,
            child: Text('−10 s', style: TextStyle(fontFamily: mono, fontSize: 10, color: Palette.faint)),
          ),
          const Positioned(
            right: 12,
            bottom: 8,
            child: Text('now', style: TextStyle(fontFamily: mono, fontSize: 10, color: Palette.faint)),
          ),
        ],
      ),
    );
  }
}

class _Readouts extends StatelessWidget {
  const _Readouts({required this.status});

  final MonitorStatus status;

  @override
  Widget build(BuildContext context) {
    final live = status.listening && status.detectorState != DetectorState.warmingUp;
    return Row(
      children: [
        Expanded(
          child: _Readout(
            label: 'BACKGROUND',
            value: live ? status.noiseRms.toStringAsFixed(3) : '—',
            unit: 'm/s²',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Readout(
            label: 'SIGNAL',
            value: live ? status.ratio.toStringAsFixed(1) : '—',
            unit: 'STA/LTA',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Readout(
            label: 'TONIGHT',
            value: status.listening ? '${status.detections}' : '—',
            unit: status.detections == 1 ? 'event' : 'events',
          ),
        ),
      ],
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.label, required this.value, required this.unit});

  final String label, value, unit;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Palette.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: labelStyle.copyWith(fontSize: 9.5)),
            const SizedBox(height: 6),
            Text(value, style: readoutStyle),
            Text(unit, style: const TextStyle(fontFamily: mono, fontSize: 10, color: Palette.faint)),
          ],
        ),
      );
}

class _Conditions extends StatelessWidget {
  const _Conditions({required this.controller});

  final MonitorController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.status;
    final settings = controller.settings;
    final (netIcon, netText, netOn) = switch ((settings.shareWithNetwork, controller.networkAvailable, s.hasLocation || settings.hasLocation)) {
      (false, _, _) => (Icons.cloud_off_rounded, 'Not sharing', false),
      (_, false, _) => (Icons.cloud_off_rounded, 'Network not set up', false),
      (_, _, false) => (Icons.location_off_rounded, 'No location', false),
      (_, null, _) => (Icons.cloud_outlined, 'Connecting', false),
      _ => (Icons.cloud_done_rounded, 'Sharing', true),
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Chip(
          icon: s.pluggedIn ? Icons.bolt_rounded : Icons.battery_std_rounded,
          text: settings.enabled ? (s.pluggedIn ? 'Charging' : 'On battery') : 'Needs charger',
          on: s.pluggedIn,
        ),
        _Chip(
          icon: Icons.bedtime_rounded,
          text: settings.nightOnly ? '${_hour(settings.startHour)}–${_hour(settings.endHour)}' : 'Any time',
          on: s.gate != GateStatus.outsideHours && settings.enabled,
        ),
        _Chip(icon: netIcon, text: netText, on: netOn),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, required this.on});

  final IconData icon;
  final String text;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = on ? Palette.amber : Palette.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: on ? const Color(0xFF221808) : Palette.surface,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: on ? Palette.amberDim : Palette.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: c),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 12.5, color: c, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _MonitoringToggle extends StatelessWidget {
  const _MonitoringToggle({required this.controller});

  final MonitorController controller;

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    final on = settings.enabled;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: on ? const Color(0xFF1A1307) : Palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: on ? Palette.amberDim : Palette.outline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _toggle(context, !on),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
          child: Row(
            children: [
              Icon(Icons.nights_stay_rounded, color: on ? Palette.amber : Palette.muted),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Overnight monitoring', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(
                      on
                          ? 'Leave it flat on a nightstand, not on the bed'
                          : 'Listens only while charging, so no battery cost',
                      style: const TextStyle(fontSize: 13, color: Palette.muted),
                    ),
                  ],
                ),
              ),
              Switch(value: on, onChanged: (v) => _toggle(context, v)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context, bool v) async {
    final warning = await controller.setEnabled(v);
    if (warning != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(warning)));
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: Text(text, style: labelStyle),
      );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, color: Palette.faint),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: const TextStyle(fontSize: 13, color: Palette.muted)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _NetworkEvents extends StatelessWidget {
  const _NetworkEvents({required this.controller});

  final MonitorController controller;

  @override
  Widget build(BuildContext context) {
    final available = controller.networkAvailable;
    if (available == null) {
      return const _EmptyCard(icon: Icons.cloud_outlined, title: 'Connecting…');
    }
    if (!available) {
      return const _EmptyCard(
        icon: Icons.cloud_off_rounded,
        title: 'Network not connected yet',
        subtitle: 'Your phone still detects shaking. Confirmations from other '
            'phones appear here once the network is set up.',
      );
    }
    final settings = controller.settings;
    if (controller.eventsError != null) {
      return _EmptyCard(
        icon: Icons.error_outline_rounded,
        title: 'Could not load events',
        subtitle: '${controller.eventsError}',
      );
    }
    final all = controller.events;
    if (all == null) {
      return const _EmptyCard(icon: Icons.cloud_outlined, title: 'Loading…');
    }
    final events = [
      for (final e in all)
        if (!settings.hasLocation ||
            distanceKm(settings.latitude!, settings.longitude!, e.latitude, e.longitude) <= _nearbyKm)
          e,
    ];
    if (events.isEmpty) {
      return const _EmptyCard(
        icon: Icons.verified_outlined,
        title: 'All quiet',
        subtitle: 'No tremors confirmed nearby in the last 7 days.',
      );
    }
    return Card(
      child: Column(
        children: [
          for (final (i, e) in events.indexed) ...[
            if (i > 0) const Divider(indent: 70),
            _EventTile(event: e, settings: settings),
          ],
        ],
      ),
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
    final c = Palette.forMmi(e.mmi);
    final parts = [
      _when(e.time),
      e.activeCount > 0 ? '${e.deviceCount} of ${e.activeCount} phones' : '${e.deviceCount} phones',
      if (settings.hasLocation)
        '${distanceKm(settings.latitude!, settings.longitude!, e.latitude, e.longitude).round()} km',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.withValues(alpha: 0.12),
              border: Border.all(color: c.withValues(alpha: 0.6)),
              boxShadow: [BoxShadow(color: c.withValues(alpha: 0.25), blurRadius: 14)],
            ),
            child: Text(
              e.mmi.toStringAsFixed(0),
              style: readoutStyle.copyWith(fontSize: 16, color: c),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        describeMmi(e.mmi),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                    ),
                    if (e.test) ...[const SizedBox(width: 8), const _Tag('TEST')],
                  ],
                ),
                const SizedBox(height: 2),
                Text(parts.join('  ·  '), style: const TextStyle(fontSize: 12.5, color: Palette.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalHistory extends StatelessWidget {
  const _LocalHistory({required this.history});

  final List<DetectionRecord> history;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const _EmptyCard(
        icon: Icons.nights_stay_outlined,
        title: 'Nothing felt yet',
        subtitle: 'Shaking this phone notices will be listed here.',
      );
    }
    final items = history.take(10).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            for (final (i, r) in items.indexed)
              _TimelineRow(record: r, first: i == 0, last: i == items.length - 1),
          ],
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.record, required this.first, required this.last});

  final DetectionRecord record;
  final bool first, last;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final dot = r.simulated ? Palette.teal : Palette.amber;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Expanded(child: Container(width: 1, color: first ? Colors.transparent : Palette.outline)),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dot,
                    boxShadow: [BoxShadow(color: dot.withValues(alpha: 0.5), blurRadius: 8)],
                  ),
                ),
                Expanded(child: Container(width: 1, color: last ? Colors.transparent : Palette.outline)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(_when(r.onset), style: const TextStyle(fontSize: 14.5)),
                            if (r.simulated) ...[const SizedBox(width: 8), const _Tag('TEST')],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${r.peakAccel.toStringAsFixed(3)} m/s²  ·  ${r.dominantFrequencyHz.toStringAsFixed(1)} Hz',
                          style: const TextStyle(fontFamily: mono, fontSize: 11.5, color: Palette.muted),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    r.uploaded ? Icons.cloud_done_rounded : Icons.phone_android_rounded,
                    size: 16,
                    color: Palette.faint,
                  ),
                ],
              ),
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
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF123230),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text, style: labelStyle.copyWith(fontSize: 9, letterSpacing: 1.2, color: Palette.teal)),
      );
}

String _hour(int h) => '${h.toString().padLeft(2, '0')}:00';

String _when(DateTime t) {
  final now = DateTime.now();
  final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final daysAgo = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
  if (daysAgo == 0) return 'Today $hm';
  if (daysAgo == 1) return 'Yesterday $hm';
  return '${t.day}/${t.month} $hm';
}
