import 'package:flutter/material.dart';

import '../detection/detector.dart';
import '../settings.dart';
import 'monitor_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final MonitorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.settings;
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            children: [
              const _Header('Detection'),
              ListTile(
                title: const Text('Sensitivity'),
                subtitle: const Text(
                  'Higher catches weaker tremors but reacts more to traffic '
                  'and footsteps.',
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<Sensitivity>(
                  segments: const [
                    ButtonSegment(value: Sensitivity.low, label: Text('Low')),
                    ButtonSegment(value: Sensitivity.medium, label: Text('Medium')),
                    ButtonSegment(value: Sensitivity.high, label: Text('High')),
                  ],
                  selected: {s.sensitivity},
                  onSelectionChanged: (v) =>
                      controller.update(s.copyWith(sensitivity: v.single)),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Only at night'),
                subtitle: const Text(
                  'Otherwise listens any time the phone is charging.',
                ),
                value: s.nightOnly,
                onChanged: (v) => controller.update(s.copyWith(nightOnly: v)),
              ),
              if (s.nightOnly)
                ListTile(
                  title: const Text('Night window'),
                  subtitle: Row(
                    children: [
                      _HourPicker(
                        value: s.startHour,
                        onChanged: (h) => controller.update(s.copyWith(startHour: h)),
                      ),
                      const Text('  to  '),
                      _HourPicker(
                        value: s.endHour,
                        onChanged: (h) => controller.update(s.copyWith(endHour: h)),
                      ),
                    ],
                  ),
                ),
              const _Header('Network'),
              SwitchListTile(
                title: const Text('Share detections'),
                subtitle: const Text(
                  'Sends anonymous detections and an approximate location so '
                  'phones across the city can confirm a tremor together.',
                ),
                value: s.shareWithNetwork,
                onChanged: (v) => controller.update(s.copyWith(shareWithNetwork: v)),
              ),
              ListTile(
                title: const Text('Location'),
                subtitle: Text(
                  s.hasLocation
                      ? '${s.latitude!.toStringAsFixed(2)}, '
                          '${s.longitude!.toStringAsFixed(2)} (rounded to about 1 km)'
                      : 'Not set',
                ),
                trailing: TextButton(
                  onPressed: () async {
                    final error = await controller.refreshLocation();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(error ?? 'Location updated'),
                      ));
                    }
                  },
                  child: const Text('Update'),
                ),
              ),
              const _Header('Testing'),
              ListTile(
                title: const Text('Simulate a tremor'),
                subtitle: Text(
                  controller.status.detectorState == DetectorState.listening
                      ? 'Adds 5 s of synthetic shaking to the sensor feed. The '
                          'detection is marked as a test everywhere.'
                      : 'Available while the phone is listening.',
                ),
                trailing: FilledButton.tonal(
                  onPressed:
                      controller.status.detectorState == DetectorState.listening
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
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Seismograph is an experiment, not an official warning '
                  'system. Follow your local authorities for earthquake alerts.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
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
        items: [
          for (var h = 0; h < 24; h++)
            DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00')),
        ],
        onChanged: (h) {
          if (h != null) onChanged(h);
        },
      );
}
