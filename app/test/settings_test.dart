import 'package:flutter_test/flutter_test.dart';
import 'package:seismograph/src/settings.dart';

void main() {
  group('isWithinHours', () {
    test('handles windows that wrap past midnight', () {
      expect(isWithinHours(23, 22, 7), isTrue);
      expect(isWithinHours(3, 22, 7), isTrue);
      expect(isWithinHours(7, 22, 7), isFalse);
      expect(isWithinHours(12, 22, 7), isFalse);
    });

    test('handles same-day windows', () {
      expect(isWithinHours(13, 12, 14), isTrue);
      expect(isWithinHours(14, 12, 14), isFalse);
    });

    test('treats equal bounds as all day', () {
      expect(isWithinHours(5, 0, 0), isTrue);
    });
  });

  group('evaluateGate', () {
    final night = DateTime(2026, 1, 1, 2);
    final noon = DateTime(2026, 1, 1, 12);
    const on = MonitorSettings(enabled: true);

    test('needs the master switch', () {
      expect(
        evaluateGate(settings: const MonitorSettings(), pluggedIn: true, now: night),
        GateStatus.disabled,
      );
    });

    test('needs the charger', () {
      expect(evaluateGate(settings: on, pluggedIn: false, now: night), GateStatus.notCharging);
    });

    test('respects the night window only when asked', () {
      expect(evaluateGate(settings: on, pluggedIn: true, now: noon), GateStatus.outsideHours);
      expect(
        evaluateGate(settings: on.copyWith(nightOnly: false), pluggedIn: true, now: noon),
        GateStatus.open,
      );
      expect(evaluateGate(settings: on, pluggedIn: true, now: night), GateStatus.open);
    });
  });
}
