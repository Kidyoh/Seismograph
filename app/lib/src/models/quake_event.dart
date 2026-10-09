import 'package:cloud_firestore/cloud_firestore.dart';

import '../geo.dart';

/// A tremor confirmed by several phones, as written by the Cloud Function.
class QuakeEvent {
  const QuakeEvent({
    required this.id,
    required this.time,
    required this.latitude,
    required this.longitude,
    required this.deviceCount,
    required this.activeCount,
    required this.maxPeak,
    required this.test,
  });

  factory QuakeEvent.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return QuakeEvent(
      id: doc.id,
      time: (d['t'] as Timestamp).toDate(),
      latitude: (d['lat'] as num).toDouble(),
      longitude: (d['lng'] as num).toDouble(),
      deviceCount: (d['deviceCount'] as num).toInt(),
      activeCount: (d['activeCount'] as num?)?.toInt() ?? 0,
      maxPeak: (d['maxPeak'] as num).toDouble(),
      test: d['test'] as bool? ?? false,
    );
  }

  final String id;
  final DateTime time;
  final double latitude, longitude;

  /// Phones that felt it.
  final int deviceCount;

  /// Phones that were listening nearby at the time.
  final int activeCount;

  /// Strongest shaking any of them recorded, m/s².
  final double maxPeak;

  /// Made from simulated detections.
  final bool test;

  double get mmi => estimateMmi(maxPeak);
}
