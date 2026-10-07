import { useEffect, useRef, useState } from 'react';
import { Polyline } from 'react-leaflet';
import { fetchRoute } from '../lib/geoutils';

const TO_PATIENT = ['assigned', 'accepted', 'enRoute'];
const TO_HOSPITAL = ['onScene', 'transporting', 'atHospital'];

export default function MissionRoute({
  mission,
  ambulancePoint,
  hospitalLocation,
  onEta,
}) {
  const [route, setRoute] = useState(null);
  const lastFetch = useRef({ point: null, at: 0, target: null });

  const target =
    (TO_PATIENT.includes(mission.status) && mission.location) ||
    (TO_HOSPITAL.includes(mission.status) && hospitalLocation) ||
    null;

  useEffect(() => {
    if (!target || !ambulancePoint) {
      setRoute(null);
      lastFetch.current = { point: null, at: 0, target: null };
      return undefined;
    }
    const last = lastFetch.current;
    const now = Date.now();
    const targetChanged =
      !last.target ||
      last.target.lat !== target.lat ||
      last.target.lng !== target.lng;
    if (last.point && !targetChanged) {
      const moved =
        Math.abs(last.point.lat - ambulancePoint.lat) > 0.0005 ||
        Math.abs(last.point.lng - ambulancePoint.lng) > 0.0005;
      if (!moved || now - last.at < 3000) return undefined;
    }
    lastFetch.current = { point: ambulancePoint, at: now, target };
    let cancelled = false;
    fetchRoute(ambulancePoint, target).then((r) => {
      if (cancelled) return;
      setRoute(r);
      onEta?.(r.durationSec, r.distanceKm);
    });
    return () => {
      cancelled = true;
    };
  }, [ambulancePoint, target, onEta]);

  if (!route) return null;
  return (
    <Polyline
      positions={route.points}
      pathOptions={{ color: '#283593', weight: 4, opacity: 0.85 }}
    />
  );
}
