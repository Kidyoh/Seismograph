import 'package:flutter_test/flutter_test.dart';
import 'package:seismograph/src/geo.dart';

void main() {
  test('coarsen rounds to two decimals', () {
    expect(coarsen(37.774929), 37.77);
    expect(coarsen(-122.419416), -122.42);
  });

  test('regionCell floors toward negative infinity', () {
    expect(regionCell(37.77, -122.42), '151:-490');
    expect(regionCell(0.1, -0.1), '0:-1');
  });

  test('distanceKm matches a known pair', () {
    // San Francisco to Oakland, roughly 13 km.
    expect(distanceKm(37.7749, -122.4194, 37.8044, -122.2712), closeTo(13.4, 0.5));
  });

  test('estimateMmi is in a plausible range', () {
    expect(estimateMmi(0.01), lessThan(2));
    expect(estimateMmi(0.5), inInclusiveRange(4, 5));
    expect(estimateMmi(3), inInclusiveRange(6, 7.5));
  });
}
