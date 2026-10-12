"use strict";

// Phase 9 — Cloud Functions for the ambulance dispatch backend.
//
// These run *alongside* the existing client write flow (patient writes a
// `requested` mission, crew advances the status). Admin-SDK writes bypass
// security rules, so no rule change is required here — locking clients out of
// direct status writes is Phase 10.
//
//   requestAmbulance  — callable: nearest-available-unit match + create the
//                       mission as `assigned` + notify the crew (FCM).
//   onMissionUpdate   — Firestore trigger: authoritative `timeline.$status`
//                       stamp, a server-computed ETA (OSRM), and an FCM data
//                       message deep-linked to the patient's mission screen.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getDatabase } = require("firebase-admin/database");
const { getMessaging } = require("firebase-admin/messaging");
const logger = require("firebase-functions/logger");

initializeApp();
const db = getFirestore();
const fcm = getMessaging();

// Resolved lazily: getDatabase() needs the project's Database URL, which is
// only auto-configured in the deployed environment (or with credentials).
let _rtdb = null;
function rtdb() {
  if (!_rtdb) _rtdb = getDatabase();
  return _rtdb;
}

// ── Status model (backend's 8 statuses) ──────────────────────────────
// The patient app folds assigned+accepted → "dispatched" (7 design statuses).
// `requested` appearing on the right-hand side means "crew rejected" (back to
// the queue with the unit cleared); `cancelled` is the patient aborting.
const LEGAL = {
  requested: ["assigned", "cancelled"],
  assigned: ["accepted", "requested", "cancelled"],
  accepted: ["enRoute", "requested", "cancelled"],
  enRoute: ["onScene", "cancelled"],
  onScene: ["transporting", "cancelled"],
  transporting: ["atHospital", "cancelled"],
  atHospital: ["resolved", "cancelled"],
  resolved: [],
  cancelled: [],
};

// Statuses whose target is a *moving* point we can route to (for server ETA).
const ROUTED_LEGS = ["assigned", "accepted", "enRoute", "transporting"];

// The `type` the patient app's FCM handler expects (it auto-opens MissionScreen
// on "dispatched"). Mirrors mapBackendStatus()'s 8→7 fold.
function designType(status) {
  if (status === "assigned" || status === "accepted") return "dispatched";
  return status;
}

// ── Geo + routing helpers ────────────────────────────────────────────
function haversineKm(a, b) {
  const R = 6371;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

// Real drive time (seconds) from OSRM; null when unreachable. Falls back to a
// straight-line 40 km/h estimate so the caller always gets a usable number.
async function routeEtaSeconds(from, to) {
  const url =
    "https://router.project-osrm.org/route/v1/driving/" +
    `${from.lng},${from.lat};${to.lng},${to.lat}?overview=false`;
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(6000) });
    if (res.ok) {
      const json = await res.json();
      const dur = json?.routes?.[0]?.duration;
      if (typeof dur === "number" && dur > 0) return Math.round(dur);
    }
  } catch (_) {
    // fall through to straight line
  }
  return Math.round((haversineKm(from, to) / 40) * 3600);
}

// ── FCM helpers ──────────────────────────────────────────────────────
// Token locations (registered by the apps in a later wiring step):
//   patient  → patients/{uid}.fcmToken
//   crew     → ambulances/{id}.crewFcmToken
// Missing tokens are a no-op, so fan-out is safe before tokens exist.
async function patientToken(patientId) {
  if (!patientId) return null;
  const snap = await db.collection("patients").doc(patientId).get();
  const tok = snap.data()?.fcmToken;
  return typeof tok === "string" ? tok : null;
}

async function crewToken(ambulanceId) {
  if (!ambulanceId) return null;
  const snap = await db.collection("ambulances").doc(ambulanceId).get();
  const tok = snap.data()?.crewFcmToken;
  return typeof tok === "string" ? tok : null;
}

async function sendData(token, payload) {
  if (!token) return;
  try {
    await fcm.send({ token, data: payload });
  } catch (e) {
    logger.warn("FCM send failed", e.message);
  }
}

// ── Nearest-unit matching ────────────────────────────────────────────
// Reads the active fleet from Firestore + live GPS from RTDB, returns the
// closest available unit id (or null).
async function nearestUnit(pickup) {
  const fleet = await db
    .collection("ambulances")
    .where("status", "==", "active")
    .get();
  const candidates = [];
  for (const doc of fleet.docs) {
    const v = doc.data();
    if (v.available === false) continue;
    const posSnap = await rtdb().ref(`positions/${doc.id}`).once("value");
    const pos = posSnap.val();
    if (pos && typeof pos.lat === "number" && typeof pos.lng === "number") {
      candidates.push({
        id: doc.id,
        km: haversineKm(pickup, { lat: pos.lat, lng: pos.lng }),
      });
    }
  }
  if (candidates.length === 0) return null;
  candidates.sort((a, b) => a.km - b.km);
  return candidates[0].id;
}

// ── Callable: requestAmbulance ───────────────────────────────────────
// Creates a mission already matched to the nearest unit and notifies its crew.
// Additive to the current flow — the dispatcher/dashboard can still assign
// manually, and the patient app keeps working via its direct write.
exports.requestAmbulance = onCall(async (request) => {
  const data = request.data || {};
  const pickup = data.pickup;
  if (
    !pickup ||
    typeof pickup.lat !== "number" ||
    typeof pickup.lng !== "number"
  ) {
    throw new HttpsError("invalid-argument", "pickup {lat,lng} is required.");
  }

  const patientId = request.auth?.uid ?? null;
  const ambulanceId = await nearestUnit(pickup);
  if (!ambulanceId) {
    throw new HttpsError("unavailable", "No available ambulance right now.");
  }

  const ref = await db.collection("missions").add({
    status: "assigned",
    patientId,
    patientPhone: data.patientPhone ?? null,
    patientName: data.patientName ?? null,
    medicalAttached: !!data.medicalAttached,
    ambulanceId,
    location: { lat: pickup.lat, lng: pickup.lng },
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    timeline: {
      requested: FieldValue.serverTimestamp(),
      assigned: FieldValue.serverTimestamp(),
    },
  });

  await notifyCrew(ambulanceId, ref.id, "assigned");
  logger.info("requestAmbulance matched", { missionId: ref.id, ambulanceId });
  return { missionId: ref.id, ambulanceId };
});

async function notifyCrew(ambulanceId, missionId, status) {
  const token = await crewToken(ambulanceId);
  await sendData(token, {
    type: designType(status),
    incidentId: missionId,
    status,
  });
}

// ── Trigger: onMissionUpdate ─────────────────────────────────────────
// Fires on every mission write. Only acts on a *status* change, and any
// server-derived patch we write back leaves the status untouched — so the echo
// re-trigger returns above without looping.
exports.onMissionUpdate = onDocumentUpdated("missions/{missionId}", async (event) => {
  const missionId = event.params.missionId;
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!after) return;

  const from = before?.status ?? "requested";
  const to = after.status ?? "requested";
  if (to === from) return; // not a status change (incl. our own echo writes)

  // Advisory validation. Hard enforcement (rejecting the write) is done by
  // security rules in Phase 10 — here we just flag it and skip side effects.
  if (!(LEGAL[from] || []).includes(to)) {
    logger.warn("illegal status transition (advisory)", { missionId, from, to });
    return;
  }

  const patch = {};

  // Authoritative timeline stamp, only if the client didn't set one.
  if (to !== "cancelled" && (after.timeline || {})[to] == null) {
    patch[`timeline.${to}`] = FieldValue.serverTimestamp();
  }

  // Server-computed ETA for legs with a routable moving target.
  if (ROUTED_LEGS.includes(to)) {
    patch.etaSeconds = await computeServerEta(after);
  }

  // Persist server-derived fields. The echo re-trigger sees no status change
  // and returns immediately.
  if (Object.keys(patch).length > 0) {
    patch.updatedAt = FieldValue.serverTimestamp();
    await event.data.after.ref.update(patch);
  }

  // FCM fan-out to the patient (data message → deep-links the mission screen).
  const token = await patientToken(after.patientId);
  await sendData(token, {
    type: designType(to),
    incidentId: missionId,
    status: to,
  });
});

// Unit position (RTDB) → target (pickup, or hospital while transporting).
async function computeServerEta(mission) {
  const ambulanceId = mission.ambulanceId;
  if (!ambulanceId) return null;
  const posSnap = await rtdb().ref(`positions/${ambulanceId}`).once("value");
  const pos = posSnap.val();
  if (!pos || typeof pos.lat !== "number" || typeof pos.lng !== "number") {
    return null;
  }
  const from = { lat: pos.lat, lng: pos.lng };

  let to = null;
  if (
    (mission.status === "transporting" || mission.status === "atHospital") &&
    mission.hospitalId
  ) {
    const h = await db.collection("hospitals").doc(mission.hospitalId).get();
    const loc = h.data()?.location;
    if (loc && typeof loc.lat === "number" && typeof loc.lng === "number") {
      to = { lat: loc.lat, lng: loc.lng };
    }
  }
  if (!to && mission.location) {
    to = { lat: mission.location.lat, lng: mission.location.lng };
  }
  if (!to) return null;

  return routeEtaSeconds(from, to);
}
