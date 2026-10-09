import { initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { setGlobalOptions } from 'firebase-functions/v2';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { defineInt } from 'firebase-functions/params';
import * as logger from 'firebase-functions/logger';

import { clusterAround, decide, effectiveTime, summarize, TriggerPoint } from './cluster';
import { cellsAround, chunk, distanceKm } from './geo';

initializeApp();
const db = getFirestore();

setGlobalOptions({ maxInstances: 20 });

const MIN_DEVICES = defineInt('MIN_DEVICES', { default: 3 });
/** Percent of listening phones nearby that must trigger. */
const MIN_PERCENT = defineInt('MIN_PERCENT', { default: 15 });
const RADIUS_KM = defineInt('RADIUS_KM', { default: 50 });

const WINDOW_MS = 30_000;
/** A device counts as listening if its heartbeat is this recent. */
const ACTIVE_MS = 25 * 60_000;
/** More triggers than this per phone per hour and it's ignored as noisy. */
const MAX_TRIGGERS_PER_HOUR = 6;
/**
 * Cells per query. Firestore expands `in` into one disjunct per value and
 * caps a query at 100 filters in total; with up to four filters per
 * disjunct, 20 cells stays well clear of that.
 */
const CELLS_PER_QUERY = 20;

/**
 * Runs for every detection a phone uploads. Looks for other phones nearby
 * that triggered at the same time; if enough did, writes or updates a
 * confirmed event.
 */
export const onTriggerCreated = onDocumentCreated('triggers/{triggerId}', async (event) => {
  const snap = event.data;
  if (!snap) return;
  const d = snap.data();

  const receivedMs = snap.createTime.toMillis();
  const seed: TriggerPoint = {
    id: snap.id,
    uid: d.uid,
    time: effectiveTime((d.clientTime as Timestamp).toMillis(), receivedMs),
    lat: d.lat,
    lng: d.lng,
    peak: d.peak,
    freq: d.freq,
  };
  const isTest = d.test === true;

  // Phones that trigger all night are on a washing machine, not a fault line.
  const recent = await db
    .collection('triggers')
    .where('uid', '==', seed.uid)
    .where('serverTime', '>=', Timestamp.fromMillis(receivedMs - 3_600_000))
    .count()
    .get();
  if (recent.data().count > MAX_TRIGGERS_PER_HOUR) {
    await snap.ref.update({ ignored: 'rate', time: Timestamp.fromMillis(seed.time) });
    logger.info('Ignoring noisy device', { uid: seed.uid, count: recent.data().count });
    return;
  }
  // Write the trusted time before querying. Of several phones triggering
  // at once, whichever function queries last then sees all the others.
  await snap.ref.update({ time: Timestamp.fromMillis(seed.time) });

  const params = {
    windowMs: WINDOW_MS,
    radiusKm: RADIUS_KM.value(),
    minDevices: MIN_DEVICES.value(),
    minFraction: MIN_PERCENT.value() / 100,
  };
  const cells = cellsAround(seed.lat, seed.lng, params.radiusKm);

  const [candidates, activeNearby] = await Promise.all([
    nearbyTriggers(cells, seed, isTest),
    countListening(cells, seed),
  ]);

  const cluster = clusterAround(seed, candidates, params);
  const decision = decide(cluster, activeNearby, params);
  logger.info('Trigger evaluated', { trigger: seed.id, test: isTest, ...decision });
  if (!decision.confirmed) return;

  const summary = summarize(cluster);
  const ref = db.collection('events').doc(summary.id);
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(ref);
    const prev = existing.data();
    tx.set(ref, {
      t: Timestamp.fromMillis(summary.time),
      lat: summary.lat,
      lng: summary.lng,
      deviceCount: Math.max(summary.deviceCount, prev?.deviceCount ?? 0),
      activeCount: Math.max(decision.activeCount, prev?.activeCount ?? 0),
      maxPeak: Math.max(summary.maxPeak, prev?.maxPeak ?? 0),
      meanFreq: summary.meanFreq,
      test: isTest,
      createdAt: prev?.createdAt ?? FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
});

/** Other triggers in the surrounding cells within the time window. */
async function nearbyTriggers(cells: string[], seed: TriggerPoint, isTest: boolean) {
  const from = Timestamp.fromMillis(seed.time - WINDOW_MS);
  const to = Timestamp.fromMillis(seed.time + WINDOW_MS);
  const snaps = await Promise.all(
    chunk(cells, CELLS_PER_QUERY).map((group) =>
      db
        .collection('triggers')
        .where('cell', 'in', group)
        .where('test', '==', isTest)
        .where('time', '>=', from)
        .where('time', '<=', to)
        .get(),
    ),
  );
  const points: TriggerPoint[] = [];
  for (const s of snaps) {
    for (const doc of s.docs) {
      const t = doc.data();
      if (doc.id === seed.id || t.ignored) continue;
      points.push({
        id: doc.id,
        uid: t.uid,
        time: (t.time as Timestamp).toMillis(),
        lat: t.lat,
        lng: t.lng,
        peak: t.peak,
        freq: t.freq,
      });
    }
  }
  return points;
}

/** Phones listening within the radius right now, from their heartbeats. */
async function countListening(cells: string[], seed: TriggerPoint) {
  const since = Timestamp.fromMillis(Date.now() - ACTIVE_MS);
  const snaps = await Promise.all(
    chunk(cells, CELLS_PER_QUERY).map((group) =>
      db
        .collection('devices')
        .where('cell', 'in', group)
        .where('listening', '==', true)
        .where('lastSeen', '>=', since)
        .get(),
    ),
  );
  let n = 0;
  for (const s of snaps) {
    for (const doc of s.docs) {
      const dev = doc.data();
      if (distanceKm(seed.lat, seed.lng, dev.lat, dev.lng) <= RADIUS_KM.value()) n++;
    }
  }
  return n;
}
