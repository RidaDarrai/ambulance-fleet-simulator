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
