import { test } from 'node:test';
import assert from 'node:assert/strict';

import { clusterAround, decide, DEFAULT_PARAMS, effectiveTime, summarize, TriggerPoint } from './cluster';
import { cellsAround, regionCell } from './geo';

const base = Date.UTC(2026, 0, 1, 3, 0, 0);
const t = (id: string, uid: string, dtMs: number, lat = 37.77, lng = -122.42, peak = 0.1): TriggerPoint => ({
  id,
  uid,
  time: base + dtMs,
  lat,
  lng,
  peak,
  freq: 3,
});

test('clusters triggers close in time and space, one per phone', () => {
  const seed = t('a', 'u1', 0);
  const cluster = clusterAround(
    seed,
    [
      t('b', 'u2', 4_000),
      t('c', 'u3', -2_000, 37.9, -122.3),
      t('d', 'u2', 1_000), // same phone as b, earlier, so it wins
      t('e', 'u4', 120_000), // too late
      t('f', 'u5', 0, 38.9, -121.0), // too far (~170 km)
    ],
    DEFAULT_PARAMS,
  );
  assert.deepEqual(
    cluster.map((p) => p.id),
    ['c', 'a', 'd'],
  );
});

test('needs enough distinct phones', () => {
  const d = decide([t('a', 'u1', 0), t('b', 'u2', 0)], 2, DEFAULT_PARAMS);
  assert.equal(d.confirmed, false);
});

test('needs a meaningful share of listening phones', () => {
  const cluster = [t('a', 'u1', 0), t('b', 'u2', 0), t('c', 'u3', 0)];
  assert.equal(decide(cluster, 100, DEFAULT_PARAMS).confirmed, false);
  assert.equal(decide(cluster, 10, DEFAULT_PARAMS).confirmed, true);
});

test('never counts fewer listening phones than triggered ones', () => {
  const cluster = [t('a', 'u1', 0), t('b', 'u2', 0), t('c', 'u3', 0)];
  const d = decide(cluster, 0, DEFAULT_PARAMS);
  assert.equal(d.activeCount, 3);
  assert.equal(d.confirmed, true);
});

test('summarizes with a stable id and the strongest peak', () => {
  const s = summarize([t('a', 'u1', 0, 37.7, -122.4, 0.1), t('b', 'u2', 500, 37.9, -122.2, 0.3)]);
  assert.equal(s.id, 'a');
  assert.equal(s.time, base);
  assert.equal(s.lat, 37.8);
  assert.equal(s.lng, -122.3);
  assert.equal(s.maxPeak, 0.3);
});

test('falls back to receive time when the phone clock is far off', () => {
  assert.equal(effectiveTime(base, base + 5_000), base);
  assert.equal(effectiveTime(base - 3_600_000, base), base - 2_000);
});

test('grid cells match the app and cover the search radius', () => {
  // Same expectations as app/test/geo_test.dart.
  assert.equal(regionCell(37.77, -122.42), '151:-490');
  assert.equal(regionCell(0.1, -0.1), '0:-1');
  const cells = cellsAround(37.77, -122.42, 50);
  assert.ok(cells.includes(regionCell(37.77, -122.42)));
  assert.ok(cells.includes(regionCell(38.2, -122.42))); // ~48 km north
  assert.ok(cells.includes(regionCell(37.77, -121.9))); // ~46 km east
  assert.ok(cells.length <= 40);
});
