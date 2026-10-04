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
 * @param {Array<{id:string,status:string,plate?:string,base?:{lat:number,lng:number}}>} ambulances active fleet (flat docs)
 * @param {Record<string,{lat:number,lng:number}>} positions live RTDB positions
 * @param {string[]} busyAmbulanceIds ids with an active mission
 * @returns {{ambulanceId:string,plate:string,distanceKm:number}|null}
 */
export function suggestNearest(target, ambulances, positions, busyAmbulanceIds) {
  let best = null;
  for (const a of ambulances) {
    if (a.status !== 'active') continue;
    if (busyAmbulanceIds.includes(a.id)) continue;
    const pos = positions[a.id] ?? a.base;
    if (!pos) continue;
    const km = haversineKm(target, pos);
    if (!best || km < best.distanceKm) {
      best = { ambulanceId: a.id, plate: a.plate ?? a.id, distanceKm: km };
    }
  }
  return best;
}

/**
 * OSRM route with straight-line fallback (40 km/h).
 * @returns {Promise<{points:[number,number][],durationSec:number,distanceKm:number}>}
 *   points are [lat,lng] pairs ready for Leaflet polylines.
 */
export async function fetchRoute(from, to) {
  try {
    const url =
      'https://router.project-osrm.org/route/v1/driving/' +
      `${from.lng},${from.lat};${to.lng},${to.lat}` +
      '?overview=full&geometries=geojson';
    const resp = await fetch(url, { signal: AbortSignal.timeout(6000) });
    if (resp.ok) {
      const json = await resp.json();
      const r = json.routes?.[0];
      if (r?.geometry?.coordinates?.length >= 2) {
        return {
          points: r.geometry.coordinates.map(([lng, lat]) => [lat, lng]),
          durationSec: r.duration,
          distanceKm: r.distance / 1000,
        };
      }
    }
  } catch {
    // fall through
  }
  const km = haversineKm(from, to);
  return {
    points: [
      [from.lat, from.lng],
      [to.lat, to.lng],
    ],
    durationSec: (km / 40) * 3600,
    distanceKm: km,
  };
}

export function etaLabel(durationSec) {
  const m = Math.round(durationSec / 60);
  if (m < 1) return '<1 min';
  if (m < 60) return `~${m} min`;
  const h = Math.floor(m / 60);
  return `~${h}h${String(m % 60).padStart(2, '0')}`;
}
