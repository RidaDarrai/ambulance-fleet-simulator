// Fleet GPS simulator: moves every active ambulance in one process, each with
// its own behavior profile. Mission-aware: an ambulance with an active mission
// drives to the patient/hospital instead of its idle behavior.
//
// Behaviors (assigned by index):
//   patrol  — random waypoint near base, pause 10-40s on arrival, 25-45 km/h
//   circuit — fixed 4-6 point loop around base, continuous, 30-50 km/h
//   cruiser — long cross-city hops between far random points, 60-90 km/h
//   parked  — mostly holding at base, short reposition hops, 15-25 km/h
//
// Usage: node scripts/fleet-sim.mjs [--interval 1000] [--speed-scale 1] [--ticks 0]

import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { getApps, initializeApp, cert } from 'firebase-admin/app';
import { getDatabase } from 'firebase-admin/database';
import { getFirestore } from 'firebase-admin/firestore';
import { advance, currentPos, targetFor, osrmRoute, ACTIVE } from './gps-sim.mjs';

// gps-sim.mjs already initializes the default app when imported; only init
// when running this file without that side effect (defensive).
if (getApps().length === 0) {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
  initializeApp({
    credential: cert(JSON.parse(readFileSync(resolve(root, 'serviceAccountKey.json'), 'utf8'))),
    databaseURL: 'https://ambulance-dispatch-sim-default-rtdb.firebaseio.com',
  });
}
const db = getFirestore();
const rtdb = getDatabase();

const BEHAVIORS = ['patrol', 'circuit', 'cruiser', 'parked'];

// City-wide bbox for cruiser hops (Casablanca).
const CITY = { latMin: 33.54, latMax: 33.62, lngMin: -7.66, lngMax: -7.55 };

const rand = (min, max) => min + Math.random() * (max - min);
const randIn = (bbox) => ({
  lat: rand(bbox.latMin, bbox.latMax),
  lng: rand(bbox.lngMin, bbox.lngMax),
});
const nearPoint = (p, deg) => ({
  lat: p.lat + rand(-deg, deg),
  lng: p.lng + rand(-deg, deg),
});

function circuitPoints(base, n) {
  const pts = [];
  const radius = rand(0.007, 0.014);
  const phase = rand(0, Math.PI * 2);
  for (let i = 0; i < n; i++) {
    const a = phase + (i / n) * Math.PI * 2;
    pts.push({
      lat: base.lat + Math.sin(a) * radius,
      lng: base.lng + Math.cos(a) * radius,
    });
  }
  return pts;
}

function makeProfile(amb, behavior) {
  const base = amb.base;
  const profile = { behavior, base, speedRange: [20, 40] };
  if (behavior === 'patrol') {
    profile.speedRange = [25, 45];
    profile.next = () => nearPoint(base, 0.012);
    profile.onArrive = () => rand(10, 40) * 1000;
  } else if (behavior === 'circuit') {
    profile.speedRange = [30, 50];
    const loop = circuitPoints(base, Math.floor(rand(4, 7)));
    let i = 0;
    profile.next = () => {
      i = (i + 1) % loop.length;
      return loop[i];
    };
    profile.onArrive = () => 0;
  } else if (behavior === 'cruiser') {
    profile.speedRange = [60, 90];
    profile.next = () => randIn(CITY);
    profile.onArrive = () => 0;
  } else {
    profile.speedRange = [15, 25];
    profile.next = () => nearPoint(base, 0.003);
    profile.onArrive = () => rand(30, 90) * 1000;
  }
  profile.speed = rand(profile.speedRange[0], profile.speedRange[1]);
  return profile;
}

async function loadFleet() {
  const snap = await db.collection('ambulances').where('status', '==', 'active').get();
  const fleet = [];
  for (const [i, d] of snap.docs.entries()) {
    const amb = { id: d.id, ...d.data() };
    const profile = makeProfile(amb, BEHAVIORS[i % BEHAVIORS.length]);
    const pos = await currentPos(amb.id, amb.base);
    fleet.push({
      amb,
      profile,
      pos,
      target: null,
      route: null,
      state: { i: 0, t: 0 },
      holdUntil: 0,
      mission: null,
      missionKey: null,
      missionSpeed: null,
    });
  }
  return fleet;
}

// Re-resolves targets for every ambulance that has an active mission. A
// mission id/status/hospital change forces a re-route; a finished mission
// drops the ambulance back into its idle behavior.
async function refreshMissions(fleet) {
  const snap = await db.collection('missions').where('status', 'in', ACTIVE).get();
  const byAmb = new Map();
  for (const d of snap.docs) {
    const m = { id: d.id, ...d.data() };
    if (m.ambulanceId) byAmb.set(m.ambulanceId, m);
  }
  for (const entry of fleet) {
    const mission = byAmb.get(entry.amb.id) ?? null;
    const target = mission ? await targetFor(mission) : null;
    const key = mission && target
      ? `${mission.id}|${mission.status}|${mission.hospitalId ?? ''}`
      : null;
    if (key === entry.missionKey) continue;
    entry.missionKey = key;
    if (key) {
      entry.mission = mission;
      entry.target = target;
      entry.route = null;
      entry.missionSpeed =
        mission.status === 'onScene' || mission.status === 'atHospital' ? 0 : 65;
      entry.holdUntil = 0;
    } else {
      entry.mission = null;
      entry.missionSpeed = null;
      entry.target = null;
      entry.route = null;
    }
  }
}

async function tick(fleet, scale) {
  const now = Date.now();
  const payload = {};
  for (const entry of fleet) {
    if (!entry.target) {
      entry.target = entry.profile.next();
      entry.route = null;
    }
    const inMission = entry.mission != null;
    const hold = !inMission && now < entry.holdUntil;
    const speedKmh = hold
      ? 0
      : (inMission ? entry.missionSpeed ?? 45 : entry.profile.speed) * scale;
    const distKm = (speedKmh / 3600) * (TICK_MS / 1000);

    if (!entry.route) {
      // Route along real streets via OSRM; fall back to a straight line if the
      // router is unreachable so the sim keeps moving either way.
      entry.route =
        (await osrmRoute(entry.pos, entry.target)) ?? [entry.pos, entry.target];
      entry.state = { i: 0, t: 0 };
    }
    const res = distKm > 0
      ? advance(entry.route, entry.state, distKm)
      : { point: entry.pos, done: false };

    entry.pos = res.point;
    if (res.done) {
      if (inMission) {
        // Mission target reached; refreshMissions decides what comes next.
        entry.mission = null;
        entry.missionKey = null;
        entry.missionSpeed = null;
        entry.target = null;
      } else {
        entry.holdUntil = now + entry.profile.onArrive();
        entry.target = null;
      }
      entry.route = null;
    }
    payload[`positions/${entry.amb.id}`] = {
      lat: +entry.pos.lat.toFixed(6),
      lng: +entry.pos.lng.toFixed(6),
      speed: Math.round(speedKmh * 10) / 10,
      updatedAt: now,
    };
  }
  await rtdb.ref().update(payload);
}

let TICK_MS = 1000;

const isMain = process.argv[1] && import.meta.url.endsWith(process.argv[1].replaceAll('\\', '/').split('/').pop());

if (isMain) {
  const args = process.argv.slice(2);
  const flag = (name, def) => {
    const i = args.indexOf(name);
    return i >= 0 ? args[i + 1] : def;
  };
  TICK_MS = parseInt(flag('--interval', '1000'), 10);
  const scale = parseFloat(flag('--speed-scale', '1'));
  const ticks = parseInt(flag('--ticks', '0'), 10);

  const fleet = await loadFleet();
  console.log(`fleet: ${fleet.length} ambulances`);
  for (const e of fleet) {
    console.log(
      `  ${e.amb.plate ?? e.amb.id} → ${e.profile.behavior} @ ${e.profile.speed.toFixed(0)} km/h`
    );
  }

  await refreshMissions(fleet);
  let missionRefreshIn = 5;
  let n = 0;
  for (;;) {
    if (missionRefreshIn <= 0) {
      await refreshMissions(fleet);
      missionRefreshIn = 5;
    }
    await tick(fleet, scale);
    missionRefreshIn -= 1;
    n += 1;
    if (n % 10 === 0) {
      const active = fleet.filter((e) => e.mission).length;
      console.log(`tick ${n} | ${fleet.length} ambulances | ${active} on mission`);
    }
    if (ticks && n >= ticks) break;
    await new Promise((r) => setTimeout(r, TICK_MS));
  }
  process.exit(0);
}
