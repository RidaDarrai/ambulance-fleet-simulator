// Seed script: creates staff users (with role claims), ambulances, hospitals.
// Idempotent: re-running upserts by email / plate / hospital name (no duplicates).
// Requires serviceAccountKey.json in project root.
// Run: node scripts/seed.mjs

import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { initializeApp, cert } from 'firebase-admin/app';
import {
  getAuth,
} from 'firebase-admin/auth';
import {
  getFirestore,
} from 'firebase-admin/firestore';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
initializeApp({
  credential: cert(JSON.parse(readFileSync(resolve(root, 'serviceAccountKey.json'), 'utf8'))),
});
const auth = getAuth();
const db = getFirestore();

const STAFF = [
  { email: 'admin@sim.local', password: 'admin1234', role: 'admin', name: 'Admin' },
  { email: 'dispatcher@sim.local', password: 'dispatch1234', role: 'dispatcher', name: 'Dispatcher One' },
  { email: 'crew@sim.local', password: 'crew12345', role: 'crew', name: 'Crew One' },
];
// crew02..crew25 — 25 crew accounts in total (incl. Crew One above).
for (let n = 2; n <= 25; n++) {
  const suffix = String(n).padStart(2, '0');
  STAFF.push({
    email: `crew${suffix}@sim.local`,
    password: 'crew12345',
    role: 'crew',
    name: `Crew ${suffix}`,
  });
}

const HOSPITALS = [
  { name: 'Central Hospital', lat: 33.5731, lng: -7.5898 },
  { name: 'Ibn Sina Hospital', lat: 33.595, lng: -7.618 },
];

// Seeded PRNG so re-runs produce the same "random" layout (mulberry32).
function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const rng = mulberry32(0xa1b2c3d4);

function shuffle(list) {
  const arr = [...list];
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

// 5x5 jittered grid centered on Casablanca: ~even spacing with a random feel.
// Each cell is jittered by up to +/-38% of its size.
function spreadBases(count) {
  const cols = 5;
  const rows = Math.ceil(count / cols);
  const center = { lat: 33.5731, lng: -7.5898 };
  const cellLat = 0.016;
  const cellLng = 0.022;
  const points = [];
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      if (points.length >= count) break;
      const lat =
        center.lat + (r - (rows - 1) / 2) * cellLat + (rng() - 0.5) * 2 * 0.38 * cellLat;
      const lng =
        center.lng + (c - (cols - 1) / 2) * cellLng + (rng() - 0.5) * 2 * 0.38 * cellLng;
      points.push({ lat: +lat.toFixed(5), lng: +lng.toFixed(5) });
    }
  }
  return points;
}

const PLATES = Array.from({ length: 25 }, (_, i) => `AMB-${String(i + 1).padStart(2, '0')}`);
// Deterministically spread plates across the grid, then shuffle so plate order
// doesn't read as rows/columns on the map.
const BASE_POINTS = shuffle(spreadBases(25));
const AMBULANCES = PLATES.map((plate, i) => ({
  plate,
  // AMB-01..25 each get their own crew account: crew01..crew25.
  crewEmail: `crew${String(i + 1).padStart(2, '0')}@sim.local`,
  status: 'active',
  baseLat: BASE_POINTS[i].lat,
  baseLng: BASE_POINTS[i].lng,
}));
// crew@sim.local is Crew One (crew01's account) — keep AMB-01 on it.
AMBULANCES[0].crewEmail = 'crew@sim.local';

async function seedStaff() {
  for (const s of STAFF) {
    let uid;
    try {
      const user = await auth.getUserByEmail(s.email);
      uid = user.uid;
    } catch {
      const created = await auth.createUser({ email: s.email, password: s.password, displayName: s.name });
      uid = created.uid;
    }
    await auth.setCustomUserClaims(uid, { role: s.role });
    await db.collection('users').doc(uid).set({ email: s.email, name: s.name, role: s.role }, { merge: true });
  }
  console.log(`staff: ${STAFF.length} users (${STAFF.filter((s) => s.role === 'crew').length} crew)`);
}

async function seedHospitals() {
  const snap = await db.collection('hospitals').get();
  const byName = new Map(snap.docs.map((d) => [d.data().name, d.ref]));
  const batch = db.batch();
  let created = 0;
  for (const h of HOSPITALS) {
    const ref = byName.get(h.name) ?? db.collection('hospitals').doc();
    if (!byName.has(h.name)) created += 1;
    batch.set(ref, { name: h.name, location: { lat: h.lat, lng: h.lng } }, { merge: true });
  }
  await batch.commit();
  console.log(`hospitals: ${HOSPITALS.length} (${created} new)`);
}

async function seedAmbulances() {
  const staff = {};
  for (const s of STAFF) {
    const u = await auth.getUserByEmail(s.email);
    staff[s.email] = u.uid;
  }
  const snap = await db.collection('ambulances').get();
  const byPlate = new Map(
    snap.docs.map((d) => [(d.data().plate ?? '').toUpperCase(), d.ref])
  );
  const batch = db.batch();
  let created = 0;
  for (const a of AMBULANCES) {
    const ref = byPlate.get(a.plate) ?? db.collection('ambulances').doc(a.plate);
    if (!byPlate.has(a.plate)) created += 1;
    batch.set(
      ref,
      {
        plate: a.plate,
        status: a.status,
        crewId: staff[a.crewEmail] ?? null,
        base: { lat: a.baseLat, lng: a.baseLng },
      },
      { merge: true }
    );
  }
  await batch.commit();
  console.log(`ambulances: ${AMBULANCES.length} (${created} new)`);
}

await seedStaff();
await seedHospitals();
await seedAmbulances();
console.log('done');
process.exit(0);
