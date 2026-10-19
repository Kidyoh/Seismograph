import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../detection/detector.dart';
import '../geo.dart';
import '../models/quake_event.dart';

/// Talks to the shared Firebase backend.
///
/// Each phone signs in anonymously. It sends:
///  * `devices/{uid}`: a heartbeat saying whether it is listening and in
///    which grid cell, so the backend knows how many phones *could* have
///    felt a tremor;
///  * `triggers/{auto}`: one document per local detection.
///
/// A Cloud Function correlates triggers and writes confirmed `events`.
///
/// Both kinds of document carry an `expireAt` time, and a Firestore TTL
/// policy deletes them after it passes. The phone can also delete them all
/// itself with [deleteMyData].
class Network {
  Network._(this._db, this.uid);

  final FirebaseFirestore _db;
  final String uid;

  /// How long a heartbeat is kept after the latest one. Each heartbeat
  /// pushes it back, so a phone that stops sharing drops out after this.
  /// `firestore.rules` allows up to a day more for clock skew.
  static const deviceRetention = Duration(days: 7);

  /// How long a detection is kept after its onset. The backend only needs
  /// minutes; the rest is for checking the network's behaviour.
  /// `firestore.rules` allows up to a day more for clock skew.
  static const triggerRetention = Duration(days: 30);

  /// Firestore allows 500 writes per batch.
  static const _deleteBatchSize = 400;
  static const _deleteTimeout = Duration(seconds: 30);

  static Future<bool>? _init;

  /// Initializes Firebase from `google-services.json`. Returns false when
  /// the app was built without one, in which case the app runs offline.
  static Future<bool> initialize() => _init ??= () async {
        try {
          if (Firebase.apps.isEmpty) await Firebase.initializeApp();
          return true;
        } catch (e) {
          debugPrint('Firebase not configured, running offline: $e');
          return false;
        }
      }();

  /// Connects and signs in, or returns null if the backend is unavailable.
  static Future<Network?> connect() async {
    if (!await initialize()) return null;
    try {
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
      if (user == null) return null;
      return Network._(FirebaseFirestore.instance, user.uid);
    } catch (e) {
      debugPrint('Could not sign in: $e');
      return null;
    }
  }

  Future<void> heartbeat({
    required double lat,
    required double lng,
    required bool listening,
  }) =>
      _db.collection('devices').doc(uid).set({
        'lat': lat,
        'lng': lng,
        'cell': regionCell(lat, lng),
        'listening': listening,
        'lastSeen': FieldValue.serverTimestamp(),
        'expireAt': Timestamp.fromDate(DateTime.now().add(deviceRetention)),
      });

  /// Writes a trigger. Firestore queues it if the phone is offline.
  Future<void> reportDetection(
    Detection d, {
    required double lat,
    required double lng,
    required bool simulated,
  }) =>
      _db.collection('triggers').add({
        'uid': uid,
        'clientTime': Timestamp.fromDate(d.onset),
        'serverTime': FieldValue.serverTimestamp(),
        'lat': lat,
        'lng': lng,
        'cell': regionCell(lat, lng),
        'peak': d.peakAccel,
        'ratio': d.maxRatio,
        'freq': d.dominantFrequencyHz,
        'sustained': d.sustainedSeconds,
        'noise': d.noiseRms,
        'test': simulated,
        'expireAt': Timestamp.fromDate(d.onset.add(triggerRetention)),
      });

  /// Deletes everything this phone has uploaded: all of its triggers, then
  /// its heartbeat. Returns how many triggers were deleted.
  ///
  /// Reads from the server only, so it throws instead of reporting success
  /// from the cache when the phone is offline. Firestore queues a write that
  /// timed out and retries it, so a retry after an error is safe.
  Future<int> deleteMyData() async {
    var deleted = 0;
    while (true) {
      final page = await _db
          .collection('triggers')
          .where('uid', isEqualTo: uid)
          .limit(_deleteBatchSize)
          .get(const GetOptions(source: Source.server))
          .timeout(_deleteTimeout);
      if (page.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in page.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit().timeout(_deleteTimeout);
      deleted += page.docs.length;
    }
    await _db.collection('devices').doc(uid).delete().timeout(_deleteTimeout);
    return deleted;
  }

  /// Confirmed events from the last [days] days, newest first.
  ///
  /// Doesn't need sign-in to be finished first, but the security rules do
  /// require an authenticated user, so call [connect] before listening.
  static Stream<List<QuakeEvent>> recentEvents({int days = 7}) {
    final since = DateTime.now().subtract(Duration(days: days));
    return FirebaseFirestore.instance
        .collection('events')
        .where('t', isGreaterThan: Timestamp.fromDate(since))
        .orderBy('t', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map(QuakeEvent.fromFirestore).toList());
  }
}
