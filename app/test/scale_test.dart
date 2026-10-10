import 'package:flutter_test/flutter_test.dart';
import 'package:seismograph/src/ui/charts/nights_chart.dart';
import 'package:seismograph/src/ui/charts/scale.dart';

void main() {
  test('niceTicks matches d3.ticks', () {
    expect(niceTicks(0, 1, 5), [0, 0.2, 0.4, 0.6, 0.8, 1]);
    expect(niceTicks(0, 10, 5), [0, 2, 4, 6, 8, 10]);
    expect(niceTicks(0, 0.037, 3), [0, 0.01, 0.02, 0.03]);
    expect(niceTicks(-10, 0, 5), [-10, -8, -6, -4, -2, 0]);
  });

  test('nice() extends the domain to round values', () {
    final s = LinearScale(0, 0.037, 100, 0).nice(3);
    expect(s.d0, 0);
    expect(s.d1, closeTo(0.04, 1e-12));
    expect(s(0.02), closeTo(50, 1e-9));
  });

  test('formatTick uses the decimals the step needs', () {
    expect(formatTick(0.02, [0, 0.01, 0.02]), '0.02');
    expect(formatTick(4, [0, 2, 4]), '4');
  });

  test('a detection after midnight belongs to the night before', () {
    expect(nightOf(DateTime(2026, 3, 5, 3)), DateTime(2026, 3, 4));
    expect(nightOf(DateTime(2026, 3, 5, 23)), DateTime(2026, 3, 5));
  });
}
