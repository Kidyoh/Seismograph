import 'package:flutter/material.dart';

import '../detection/detector.dart';
import '../settings.dart';
import 'monitor_controller.dart';
import 'theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final MonitorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.settings;
        final canSimulate = controller.status.detectorState == DetectorState.listening;
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              _Group(
                label: 'DETECTION',
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Sensitivity', style: TextStyle(fontSize: 16)),
                        const SizedBox(height: 2),
                        const Text(
                          'Higher catches weaker tremors but reacts more to traffic and footsteps.',
                          style: TextStyle(fontSize: 13, color: Palette.muted),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<Sensitivity>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: Sensitivity.low, label: Text('Low')),
                              ButtonSegment(value: Sensitivity.medium, label: Text('Medium')),
                              ButtonSegment(value: Sensitivity.high, label: Text('High')),
                            ],
                            selected: {s.sensitivity},
                            onSelectionChanged: (v) => controller.update(s.copyWith(sensitivity: v.single)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              _Group(
                label: 'SCHEDULE',
                children: [
                  SwitchListTile(
                    title: const Text('Only at night'),
                    subtitle: const Text('Otherwise listens any time the phone is charging.'),
                    value: s.nightOnly,
                    onChanged: (v) => controller.update(s.copyWith(nightOnly: v)),
                  ),
                  if (s.nightOnly)
                    ListTile(
                      title: const Text('Night window'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _HourPicker(
                            value: s.startHour,
                            onChanged: (h) => controller.update(s.copyWith(startHour: h)),
                          ),
                          const Text('  –  ', style: TextStyle(color: Palette.muted)),
                          _HourPicker(
                            value: s.endHour,
                            onChanged: (h) => controller.update(s.copyWith(endHour: h)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              _Group(
                label: 'NETWORK',
                children: [
                  SwitchListTile(
                    title: const Text('Share detections'),
                    subtitle: const Text(
                      'Anonymous detections and an approximate location, so phones '
                      'across the city can confirm a tremor together.',
                    ),
                    value: s.shareWithNetwork,
                    onChanged: (v) => controller.update(s.copyWith(shareWithNetwork: v)),
                  ),
                  ListTile(
                    title: const Text('Location'),
                    subtitle: Text(
                      s.hasLocation
                          ? '${s.latitude!.toStringAsFixed(2)}, ${s.longitude!.toStringAsFixed(2)}  ·  about 1 km'
                          : 'Not set',
                      style: s.hasLocation ? const TextStyle(fontFamily: mono, fontSize: 12.5, color: Palette.muted) : null,
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        final error = await controller.refreshLocation();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(error ?? 'Location updated')),
                          );
                        }
                      },
                      child: const Text('Update'),
                    ),
                  ),
                ],
              ),
              _Group(
                label: 'TESTING',
                children: [
                  ListTile(
                    title: const Text('Simulate a tremor'),
                    subtitle: Text(
                      canSimulate
                          ? '5 seconds of synthetic shaking through the real detector. Marked as a test everywhere.'
                          : 'Available while the phone is listening.',
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: canSimulate
                          ? () {
                              controller.simulate();
                              Navigator.of(context).pop();
                            }
                          : null,
                      child: const Text('Shake'),
                    ),
                  ),
                  ListTile(
                    title: const Text('Clear detection history'),
                    trailing: TextButton(
                      onPressed: controller.history.isEmpty ? null : controller.clearHistory,
                      child: const Text('Clear'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const Text(
                'Seismograph is an experiment, not an official warning system. '
                'Follow your local authorities for earthquake alerts.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Palette.faint, height: 1.5),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A titled card of settings rows.
class _Group extends StatelessWidget {
  const _Group({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text(label, style: labelStyle),
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (i, c) in children.indexed) ...[
                    if (i > 0) const Divider(indent: 18, endIndent: 18),
                    c,
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}

class _HourPicker extends StatelessWidget {
  const _HourPicker({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButton<int>(
        value: value,
        underline: const SizedBox.shrink(),
        dropdownColor: Palette.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        style: const TextStyle(fontFamily: mono, fontSize: 15, color: Palette.amber),
        items: [
          for (var h = 0; h < 24; h++)
            DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00')),
        ],
        onChanged: (h) {
          if (h != null) onChanged(h);
        },
      );
}
