// Seed script: creates staff users (with role claims), ambulances, hospitals.
// Requires serviceAccountKey.json in project root (gitignored).
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

const HOSPITALS = [
  { name: 'Central Hospital', lat: 33.5731, lng: -7.5898 },
  { name: 'Ibn Sina Hospital', lat: 33.595, lng: -7.618 },
];

const AMBULANCES = [
  { plate: 'AMB-01', crewEmail: 'crew@sim.local', status: 'active', baseLat: 33.578, baseLng: -7.595 },
  { plate: 'AMB-02', crewEmail: null, status: 'active', baseLat: 33.588, baseLng: -7.605 },
  { plate: 'AMB-03', crewEmail: null, status: 'maintenance', baseLat: 33.57, baseLng: -7.58 },
];

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
    console.log(`staff: ${s.email} (${s.role}) uid=${uid}`);
  }
}

async function seedHospitals() {
  const batch = db.batch();
  for (const h of HOSPITALS) {
    const ref = db.collection('hospitals').doc();
    batch.set(ref, { name: h.name, location: { lat: h.lat, lng: h.lng } });
  }
  await batch.commit();
  console.log(`hospitals: ${HOSPITALS.length}`);
}

async function seedAmbulances() {
  const staff = {};
  for (const s of STAFF) {
    const u = await auth.getUserByEmail(s.email);
    staff[s.email] = u.uid;
  }
  const batch = db.batch();
  for (const a of AMBULANCES) {
    const ref = db.collection('ambulances').doc();
    batch.set(ref, {
      plate: a.plate,
      status: a.status,
      crewId: a.crewEmail ? staff[a.crewEmail] : null,
      base: { lat: a.baseLat, lng: a.baseLng },
    });
  }
  await batch.commit();
  console.log(`ambulances: ${AMBULANCES.length}`);
}

await seedStaff();
await seedHospitals();
await seedAmbulances();
console.log('done');
process.exit(0);
