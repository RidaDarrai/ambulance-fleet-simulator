import { useEffect, useMemo, useState } from 'react';
import {
  collection,
  doc,
  onSnapshot,
  updateDoc,
  getDoc,
  serverTimestamp,
} from 'firebase/firestore';
import { ref, onValue } from 'firebase/database';
import { MapContainer, TileLayer, Marker, Popup } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { db, rtdb } from '../lib/firebase';
import { suggestNearest, ACTIVE_STATUSES } from '../lib/geoutils';
import MissionTimeline from '../components/MissionTimeline';
import MissionRoute from '../components/MissionRoute';

const STATUS_LABELS = {
  requested: 'Requested',
  assigned: 'Assigned',
  accepted: 'Accepted',
  enRoute: 'En route',
  onScene: 'On scene',
  transporting: 'Transporting',
  atHospital: 'At hospital',
  resolved: 'Resolved',
};

const icon = (cls, label) =>
  L.divIcon({
    className: '',
    html: `<div class="mk ${cls}">${label}</div>`,
    iconSize: [26, 26],
    iconAnchor: [13, 13],
  });

const ambIcon = icon('mk-amb', 'A');
const patientIcon = icon('mk-patient', 'P');
const suggestedIcon = icon('mk-sug', '★');

export default function Dispatcher() {
  const [missions, setMissions] = useState([]);
  const [ambulances, setAmbulances] = useState([]);
  const [positions, setPositions] = useState({});
  const [selectedId, setSelectedId] = useState(null);
  const [suggestion, setSuggestion] = useState(null);
  const [manualPick, setManualPick] = useState('');
  const [patientInfo, setPatientInfo] = useState(null);
  const [busy, setBusy] = useState(false);
  const [loadError, setLoadError] = useState(null);

  useEffect(() => {
    const unsubMissions = onSnapshot(
      collection(db, 'missions'),
      (snap) => setMissions(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      (err) => setLoadError(`missions: ${err.message}`)
    );
    const unsubAmbulances = onSnapshot(
      collection(db, 'ambulances'),
      (snap) => setAmbulances(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      (err) => setLoadError(`ambulances: ${err.message}`)
    );
    const unsubPositions = onValue(
      ref(rtdb, 'positions'),
      (snap) => setPositions(snap.val() || {}),
      (err) => setLoadError(`positions: ${err.message}`)
    );
    return () => {
      unsubMissions();
      unsubAmbulances();
      unsubPositions();
    };
  }, []);

  const queue = useMemo(
    () =>
      missions
        .filter((m) => m.status === 'requested')
        .sort(
          (a, b) =>
            (a.createdAt?.toMillis?.() ?? 0) - (b.createdAt?.toMillis?.() ?? 0)
        ),
    [missions]
  );

  const active = useMemo(
    () => missions.filter((m) => ACTIVE_STATUSES.includes(m.status)),
    [missions]
  );

  const selected = missions.find((m) => m.id === selectedId) ?? null;

  useEffect(() => {
    setSuggestion(null);
    setPatientInfo(null);
    if (!selected?.patientId) return;
    getDoc(doc(db, 'patients', selected.patientId)).then((snap) => {
      if (snap.exists()) setPatientInfo(snap.data());
    });
  }, [selectedId]); // eslint-disable-line react-hooks/exhaustive-deps

  const busyIds = useMemo(
    () => active.map((m) => m.ambulanceId).filter(Boolean),
    [active]
  );

  function onSuggest() {
    if (!selected) return;
    const s = suggestNearest(
      selected.location,
      ambulances,
      positions,
      busyIds
    );
    setSuggestion(s);
  }

  async function assign(ambulanceId) {
    if (!selected || !ambulanceId) return;
    setBusy(true);
    try {
      await updateDoc(doc(db, 'missions', selected.id), {
        status: 'assigned',
        ambulanceId,
        suggestedDistanceKm: suggestion?.distanceKm ?? null,
        assignedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
        'timeline.assigned': serverTimestamp(),
      });
      setSelectedId(null);
      setSuggestion(null);
    } finally {
      setBusy(false);
    }
  }

  const fleetPoints = ambulances
    .filter((a) => a.status === 'active')
    .map((a) => ({
      id: a.id,
      plate: a.plate ?? a.id,
      point: positions[a.id] ?? a.base,
      status: a.status,
    }))
    .filter((a) => a.point);

  const selectedAmbPoint = selected?.ambulanceId
    ? (positions[selected.ambulanceId] ??
      fleetPoints.find((a) => a.id === selected.ambulanceId)?.point ??
      ambulances.find((a) => a.id === selected.ambulanceId)?.base)
    : null;

  return (
    <div className="dispatcher-layout">
      <aside className="queue-pane">
        {loadError && <div className="crash-box">Load error: {loadError}</div>}
        <h3>Request queue ({queue.length})</h3>
        {queue.length === 0 && (
          <p className="muted">No pending requests.</p>
        )}
        <ul className="queue-list">
          {queue.map((m) => (
            <li
              key={m.id}
              className={m.id === selectedId ? 'selected' : ''}
              onClick={() => setSelectedId(m.id)}
            >
              <strong>#{m.id.slice(0, 6)}</strong>{' '}
              <span className="muted">
                {m.location?.lat?.toFixed(4)}, {m.location?.lng?.toFixed(4)}
              </span>
              {m.patientId && <span className="badge">profile</span>}
            </li>
          ))}
        </ul>

        {selected?.status === 'requested' && (
          <div className="request-placeholder">
            <strong>Request #{selected.id.slice(0, 6)}</strong>
            <p className="muted">
              Location: {selected.location?.lat?.toFixed(4)},{' '}
              {selected.location?.lng?.toFixed(4)}
            </p>
            {patientInfo ? (
              <div className="patient-info">
                <p>
                  <b>Blood:</b> {patientInfo.bloodType || '—'}
                </p>
                <p>
                  <b>Allergies:</b> {patientInfo.allergies || '—'}
                </p>
                <p>
                  <b>Conditions:</b> {patientInfo.conditions || '—'}
                </p>
                <p>
                  <b>Contact:</b> {patientInfo.emergencyContact || '—'}
                </p>
              </div>
            ) : (
              <p className="muted">Guest caller — no medical profile.</p>
            )}

            <button onClick={onSuggest} disabled={busy}>
              Suggest nearest unit
            </button>
            {suggestion && (
              <div className="suggestion">
                <span>
                  {suggestion.plate} — {suggestion.distanceKm.toFixed(2)} km
                </span>
                <button
                  disabled={busy}
                  onClick={() => assign(suggestion.ambulanceId)}
                >
                  Assign
                </button>
              </div>
            )}

            <select
              value={manualPick}
              onChange={(e) => setManualPick(e.target.value)}
            >
              <option value="">— manual pick —</option>
              {fleetPoints
                .filter((a) => !busyIds.includes(a.id))
                .map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.plate}
                  </option>
                ))}
            </select>
            <button
              disabled={busy || !manualPick}
              onClick={() => assign(manualPick)}
            >
              Assign selected
            </button>
          </div>
        )}

        {selected && selected.status !== 'requested' && (
          <div className="request-placeholder">
            <strong>Mission #{selected.id.slice(0, 6)}</strong>{' '}
            <span className={`status st-${selected.status}`}>
              {STATUS_LABELS[selected.status] ?? selected.status}
            </span>
            <p className="muted">
              Ambulance:{' '}
              {fleetPoints.find((a) => a.id === selected.ambulanceId)?.plate ??
                selected.ambulanceId ??
                '—'}
            </p>
            <p className="muted">
              Patient at {selected.location?.lat?.toFixed(4)},{' '}
              {selected.location?.lng?.toFixed(4)}
            </p>
            <MissionTimeline mission={selected} />
          </div>
        )}

        <h3>Active missions ({active.length})</h3>
        <ul className="queue-list">
          {active.map((m) => (
            <li
              key={m.id}
              className={m.id === selectedId ? 'selected' : ''}
              onClick={() => setSelectedId(m.id)}
            >
              <strong>#{m.id.slice(0, 6)}</strong>{' '}
              <span className={`status st-${m.status}`}>
                {STATUS_LABELS[m.status] ?? m.status}
              </span>{' '}
              <span className="muted">
                {fleetPoints.find((a) => a.id === m.ambulanceId)?.plate ??
                  m.ambulanceId}
              </span>
            </li>
          ))}
        </ul>
      </aside>

      <main className="map-pane">
        <MapContainer
          center={[33.5731, -7.5898]}
          zoom={12}
          style={{ height: '100%', width: '100%' }}
        >
          <TileLayer
            url="https://tile.openstreetmap.org/{z}/{x}/{y}.png"
            attribution="&copy; OpenStreetMap contributors"
          />
          {fleetPoints.map((a) => (
            <Marker
              key={a.id}
              position={[a.point.lat, a.point.lng]}
              icon={
                suggestion?.ambulanceId === a.id ? suggestedIcon : ambIcon
              }
            >
              <Popup>
                {a.plate}
                <br />
                {a.status}
              </Popup>
            </Marker>
          ))}
          {selected?.location && (
            <Marker
              position={[selected.location.lat, selected.location.lng]}
              icon={patientIcon}
            >
              <Popup>Emergency request #{selected.id.slice(0, 6)}</Popup>
            </Marker>
          )}
          {selected?.ambulanceId && selectedAmbPoint && (
            <MissionRoute
              key={selected.id}
              mission={selected}
              ambulancePoint={selectedAmbPoint}
            />
          )}
        </MapContainer>
      </main>
    </div>
  );
}
