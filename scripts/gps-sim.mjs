// GPS simulator: writes live positions to RTDB for demo ambulances.
// Usage: node scripts/gps-sim.mjs AMB-01 [--speed 60]

import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { initializeApp, cert } from 'firebase-admin/app';
import { getDatabase } from 'firebase-admin/database';
import { getFirestore } from 'firebase-admin/firestore';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
initializeApp({
  credential: cert(JSON.parse(readFileSync(resolve(root, 'serviceAccountKey.json'), 'utf8'))),
  databaseURL: 'https://ambulance-dispatch-sim-default-rtdb.firebaseio.com',
});
const db = getFirestore();
const rtdb = getDatabase();

export async function findAmbulance(ref) {
  const byId = await db.collection('ambulances').doc(ref).get();
  if (byId.exists) return { id: byId.id, ...byId.data() };
  const snap = await db
    .collection('ambulances')
    .get();
  const found = snap.docs.find(
    (d) => (d.data().plate ?? '').toUpperCase() === ref.toUpperCase()
  );
  return found ? { id: found.id, ...found.data() } : null;
}

export async function writePosition(ambulanceId, lat, lng, speedKmh = 0) {
  await rtdb.ref(`positions/${ambulanceId}`).set({
    lat,
    lng,
    speed: Math.round(speedKmh * 10) / 10,
    updatedAt: Date.now(),
  });
}

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

export function interp(a, b, t) {
  return { lat: a.lat + (b.lat - a.lat) * t, lng: a.lng + (b.lng - a.lng) * t };
}

// ── OSRM street routing ───────────────────────────────────────────────
// Returns a street-following polyline [{lat,lng},...] between two points, or
// null when the router is unreachable/rate-limited (caller falls back to a
// straight line). Calls are serialized with a minimum gap so the public demo
// server (router.project-osrm.org) isn't hammered when a whole fleet needs a
// fresh route on the same tick.
let _osrmAt = 0;
let _osrmChain = Promise.resolve();

async function _osrmFetch(from, to) {
  const url =
    'https://router.project-osrm.org/route/v1/driving/' +
    `${from.lng},${from.lat};${to.lng},${to.lat}` +
    '?overview=full&geometries=geojson';
  try {
    const wait = Math.max(0, 400 - (Date.now() - _osrmAt));
    if (wait) await new Promise((r) => setTimeout(r, wait));
    _osrmAt = Date.now();
    const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
    if (!res.ok) return null;
    const json = await res.json();
    const coords = json?.routes?.[0]?.geometry?.coordinates;
    if (!Array.isArray(coords) || coords.length < 2) return null;
    return coords.map(([lng, lat]) => ({ lat, lng }));
  } catch {
    return null;
  }
}

export function osrmRoute(from, to) {
  const run = _osrmChain.then(() => _osrmFetch(from, to));
  _osrmChain = run.catch(() => {});
  return run;
}

// Advances distKm along route; mutates state {i, t} (segment index + km into it).
export function advance(route, state, distKm) {
  for (let guard = 0; guard < 1000; guard++) {
    if (state.i >= route.length - 1) {
      return { point: route[route.length - 1], done: true };
    }
    const a = route[state.i];
    const b = route[state.i + 1];
    const segLen = haversineKm(a, b);
    const remaining = segLen - state.t;
    if (distKm < remaining) {
      state.t += distKm;
      const f = segLen === 0 ? 1 : state.t / segLen;
      return { point: interp(a, b, f), done: false };
    }
    distKm -= remaining;
    state.i += 1;
    state.t = 0;
  }
  return { point: route[route.length - 1], done: true };
}

export const ACTIVE = [
  'assigned',
  'accepted',
  'enRoute',
  'onScene',
  'transporting',
  'atHospital',
];

export async function currentPos(ambulanceId, fallback) {
  const snap = await rtdb.ref(`positions/${ambulanceId}`).once('value');
  const v = snap.val();
  if (v && typeof v.lat === 'number') return { lat: v.lat, lng: v.lng };
  return fallback;
}

export async function activeMission(ambulanceId) {
  const snap = await db
    .collection('missions')
    .where('ambulanceId', '==', ambulanceId)
    .get();
  return snap.docs
    .map((d) => ({ id: d.id, ...d.data() }))
    .find((m) => ACTIVE.includes(m.status)) ?? null;
}

export async function targetFor(mission) {
  if (!mission) return null;
  if (mission.hospitalId) {
    const h = await db.collection('hospitals').doc(mission.hospitalId).get();
    if (h.exists && ['transporting', 'atHospital'].includes(mission.status)) {
      return h.data().location;
    }
  }
  if (['assigned', 'accepted', 'enRoute', 'onScene'].includes(mission.status)) {
    return mission.location;
  }
  return null;
}

const isMain = process.argv[1] && import.meta.url.endsWith(process.argv[1].replaceAll('\\', '/').split('/').pop());

if (isMain) {
  const args = process.argv.slice(2);
  const flag = (name, def) => {
    const i = args.indexOf(name);
    return i >= 0 ? args[i + 1] : def;
  };
  const ref = args[0] && !args[0].startsWith('--') ? args[0] : null;
  const speed = parseFloat(flag('--speed', '120'));
  const ticks = parseInt(flag('--ticks', '0'), 10);
  const intervalMs = parseInt(flag('--interval', '1000'), 10);
  const toIdx = args.indexOf('--to');
  const manualTo =
    toIdx >= 0
      ? { lat: parseFloat(args[toIdx + 1]), lng: parseFloat(args[toIdx + 2]) }
      : null;

  if (!ref) {
    console.error(
      'Usage: node scripts/gps-sim.mjs <AMB-01|id> [--to lat lng] [--speed 120] [--ticks N] [--interval ms]'
    );
    process.exit(1);
  }
  const amb = await findAmbulance(ref);
  if (!amb) {
    console.error(`Ambulance not found: ${ref}`);
    process.exit(1);
  }

  let route = null;
  let state = { i: 0, t: 0 };
  let lastKey = null;

  async function refreshRoute() {
    let target = manualTo;
    let key = 'manual';
    if (!manualTo) {
      const mission = await activeMission(amb.id);
      target = await targetFor(mission);
      key = `${mission?.status ?? 'idle'}|${mission?.hospitalId ?? ''}`;
    }
    if (key === lastKey && route) return;
    const start = await currentPos(amb.id, amb.base);
    route = target ? (await osrmRoute(start, target)) ?? [start, target] : [start, start];
    state = { i: 0, t: 0 };
    lastKey = key;
  }

  console.log(
    `simulating ${amb.plate} (${amb.id}) at ${speed} km/h${manualTo ? ` → ${manualTo.lat},${manualTo.lng}` : ' (mission-aware)'}`
  );

  let n = 0;
  for (;;) {
    await refreshRoute();
    const distKm = (speed / 3600) * (intervalMs / 1000);
    const res = advance(route, state, distKm);
    await writePosition(
      amb.id,
      res.point.lat,
      res.point.lng,
      res.done ? 0 : speed
    );
    console.log(
      `  ${res.point.lat.toFixed(5)},${res.point.lng.toFixed(5)} ${res.done ? 'HOLD' : 'moving'} [${lastKey}]`
    );
    n += 1;
    if (ticks && n >= ticks) break;
    if (res.done && manualTo) {
      console.log('target reached');
      break;
    }
    await new Promise((r) => setTimeout(r, intervalMs));
  }
  process.exit(0);
}
