import 'dart:math' as math;

/// Size of the grid cells used to look up nearby phones, in degrees.
///
/// Must match `CELL_DEG` in `functions/src/geo.ts`.
const cellDegrees = 0.25;

/// Rounds a coordinate to about 1 km so a phone never reports where exactly
/// it sleeps.
double coarsen(double degrees) => (degrees * 100).roundToDouble() / 100;

/// Grid cell id for a location, e.g. `"151:-489"`.
String regionCell(double lat, double lng) =>
    '${(lat / cellDegrees).floor()}:${(lng / cellDegrees).floor()}';

/// Great-circle distance in kilometres.
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// Rough Modified Mercalli Intensity from peak ground acceleration (m/s²),
/// after Wald et al. (1999). Phones on furniture overshoot real ground
/// motion, so treat this as a ballpark.
double estimateMmi(double pgaMs2) {
  final pgaCm = math.max(pgaMs2 * 100, 0.01);
  final mmi = 3.66 * math.log(pgaCm) / math.ln10 - 1.66;
  return mmi.clamp(1, 10).toDouble();
}

/// Short description of an MMI value.
String describeMmi(double mmi) {
  if (mmi < 2) return 'Not felt';
  if (mmi < 3) return 'Weak';
  if (mmi < 4) return 'Light';
  if (mmi < 5) return 'Moderate';
  if (mmi < 6) return 'Strong';
  if (mmi < 7) return 'Very strong';
  if (mmi < 8) return 'Severe';
  return 'Violent';
}
