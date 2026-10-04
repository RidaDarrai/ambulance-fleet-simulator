// Nearest-unit suggestion (Haversine) — client-side stand-in for a
// Cloud Function (Blaze plan required for functions).

export function haversineKm(a, b) {
  const R = 6371;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

export const ACTIVE_STATUSES = [
  'assigned',
  'accepted',
  'enRoute',
  'onScene',
  'transporting',
  'atHospital',
];

/**
 * @param {{lat:number,lng:number}} target mission location
 * @param {Array<{id:string,data:object}>} ambulances active fleet
 * @param {Record<string,{lat:number,lng:number}>} positions live RTDB positions
 * @param {string[]} busyAmbulanceIds ids with an active mission
 * @returns {{ambulanceId:string,plate:string,distanceKm:number}|null}
 */
export function suggestNearest(target, ambulances, positions, busyAmbulanceIds) {
  let best = null;
  for (const a of ambulances) {
    if (a.data.status !== 'active') continue;
    if (busyAmbulanceIds.includes(a.id)) continue;
    const pos = positions[a.id] ?? a.data.base;
    if (!pos) continue;
    const km = haversineKm(target, pos);
    if (!best || km < best.distanceKm) {
      best = { ambulanceId: a.id, plate: a.data.plate ?? a.id, distanceKm: km };
    }
  }
  return best;
}
