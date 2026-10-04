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

const isMain = process.argv[1] && import.meta.url.endsWith(process.argv[1].replaceAll('\\', '/').split('/').pop());

if (isMain) {
  const ref = process.argv[2];
  if (!ref) {
    console.error('Usage: node scripts/gps-sim.mjs <AMB-01|ambulanceId>');
    process.exit(1);
  }
  const amb = await findAmbulance(ref);
  if (!amb) {
    console.error(`Ambulance not found: ${ref}`);
    process.exit(1);
  }
  if (!amb.base) {
    console.error(`Ambulance ${amb.plate} has no base coordinates`);
    process.exit(1);
  }
  await writePosition(amb.id, amb.base.lat, amb.base.lng, 0);
  console.log(`position written for ${amb.plate} (${amb.id}) at base ${amb.base.lat},${amb.base.lng}`);
  process.exit(0);
}
