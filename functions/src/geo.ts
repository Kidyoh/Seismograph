/** Grid cell size in degrees. Must match `cellDegrees` in the app's geo.dart. */
export const CELL_DEG = 0.25;

export function regionCell(lat: number, lng: number): string {
  return `${Math.floor(lat / CELL_DEG)}:${Math.floor(lng / CELL_DEG)}`;
}

/** Great-circle distance in kilometres. */
export function distanceKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.sqrt(a));
}

/** Every grid cell that overlaps a circle of `radiusKm` around a point. */
export function cellsAround(lat: number, lng: number, radiusKm: number): string[] {
  const dLat = radiusKm / 111.32;
  // Longitude degrees shrink toward the poles; clamp to avoid blowing up.
  const dLng = radiusKm / (111.32 * Math.max(Math.cos((lat * Math.PI) / 180), 0.1));
  const lat0 = Math.floor((lat - dLat) / CELL_DEG);
  const lat1 = Math.floor((lat + dLat) / CELL_DEG);
  const lng0 = Math.floor((lng - dLng) / CELL_DEG);
  const lng1 = Math.floor((lng + dLng) / CELL_DEG);
  const cells: string[] = [];
  for (let i = lat0; i <= lat1; i++) {
    for (let j = lng0; j <= lng1; j++) cells.push(`${i}:${j}`);
  }
  return cells;
}

export function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}
