import { distanceKm } from './geo';

/** A phone's detection, normalized for clustering. */
export interface TriggerPoint {
  id: string;
  uid: string;
  /** Onset, ms since epoch. */
  time: number;
  lat: number;
  lng: number;
  /** Peak acceleration, m/s². */
  peak: number;
  /** Dominant frequency, Hz. */
  freq: number;
}

export interface ClusterParams {
  /** Triggers within this many ms of each other can belong together. */
  windowMs: number;
  /** ...and within this distance. */
  radiusKm: number;
  /** Distinct phones needed to confirm. */
  minDevices: number;
  /** Share of listening phones nearby that must have triggered. */
  minFraction: number;
}

export const DEFAULT_PARAMS: ClusterParams = {
  // Seismic waves cross 50 km in roughly 10–15 s; phone clocks drift a few
  // seconds. 30 s is generous for both.
  windowMs: 30_000,
  radiusKm: 50,
  minDevices: 3,
  minFraction: 0.15,
};

/**
 * Triggers that plausibly felt the same shaking as `seed`: close in time
 * and space, one per phone (its earliest).
 */
export function clusterAround(
  seed: TriggerPoint,
  candidates: TriggerPoint[],
  p: ClusterParams,
): TriggerPoint[] {
  const byUid = new Map<string, TriggerPoint>();
  for (const t of [seed, ...candidates]) {
    if (Math.abs(t.time - seed.time) > p.windowMs) continue;
    if (distanceKm(seed.lat, seed.lng, t.lat, t.lng) > p.radiusKm) continue;
    const prev = byUid.get(t.uid);
    if (!prev || t.time < prev.time || (t.time === prev.time && t.id < prev.id)) {
      byUid.set(t.uid, t);
    }
  }
  return [...byUid.values()].sort((a, b) => a.time - b.time || a.id.localeCompare(b.id));
}

export interface Decision {
  confirmed: boolean;
  deviceCount: number;
  activeCount: number;
  reason: string;
}

/**
 * Whether a cluster is a real tremor. Requires several independent phones
 * and a meaningful share of the phones that were listening nearby, so one
 * busy street in a dense area can't confirm on its own.
 */
export function decide(cluster: TriggerPoint[], activeNearby: number, p: ClusterParams): Decision {
  const deviceCount = cluster.length;
  // A phone that triggered was listening, even if its heartbeat is stale.
  const activeCount = Math.max(activeNearby, deviceCount);
  if (deviceCount < p.minDevices) {
    return { confirmed: false, deviceCount, activeCount, reason: `only ${deviceCount} phone(s)` };
  }
  const fraction = deviceCount / activeCount;
  if (fraction < p.minFraction) {
    return {
      confirmed: false,
      deviceCount,
      activeCount,
      reason: `${deviceCount}/${activeCount} phones is below ${p.minFraction}`,
    };
  }
  return { confirmed: true, deviceCount, activeCount, reason: 'confirmed' };
}

export interface EventSummary {
  /** Stable id: the earliest trigger in the cluster. */
  id: string;
  time: number;
  lat: number;
  lng: number;
  deviceCount: number;
  maxPeak: number;
  meanFreq: number;
}

export function summarize(cluster: TriggerPoint[]): EventSummary {
  if (cluster.length === 0) throw new Error('empty cluster');
  const n = cluster.length;
  const round = (v: number) => Math.round(v * 100) / 100;
  return {
    id: cluster[0].id,
    time: cluster[0].time,
    lat: round(cluster.reduce((s, t) => s + t.lat, 0) / n),
    lng: round(cluster.reduce((s, t) => s + t.lng, 0) / n),
    deviceCount: n,
    maxPeak: Math.max(...cluster.map((t) => t.peak)),
    meanFreq: cluster.reduce((s, t) => s + t.freq, 0) / n,
  };
}

/**
 * Picks the onset time to trust. Phone clocks are usually NTP-synced, but a
 * badly wrong clock would scatter a trigger outside every window, so fall
 * back to when the server received it.
 */
export function effectiveTime(clientMs: number, receivedMs: number, maxSkewMs = 120_000): number {
  if (Math.abs(receivedMs - clientMs) <= maxSkewMs) return clientMs;
  // Detections are uploaded about 2 s after onset.
  return receivedMs - 2_000;
}
