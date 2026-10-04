import { useEffect, useRef, useState } from 'react';
import { Polyline } from 'react-leaflet';
import { fetchRoute } from '../lib/geoutils';

const TO_PATIENT = ['assigned', 'accepted', 'enRoute'];

export default function MissionRoute({ mission, ambulancePoint, onEta }) {
  const [route, setRoute] = useState(null);
  const lastFetch = useRef({ point: null, at: 0 });

  const toPatient = TO_PATIENT.includes(mission.status);
  const patient = mission.location;

  useEffect(() => {
    if (!toPatient || !ambulancePoint || !patient) {
      setRoute(null);
      return undefined;
    }
    const last = lastFetch.current;
    const now = Date.now();
    if (last.point) {
      const moved =
        Math.abs(last.point.lat - ambulancePoint.lat) > 0.0005 ||
        Math.abs(last.point.lng - ambulancePoint.lng) > 0.0005;
      if (!moved || now - last.at < 3000) return undefined;
    }
    lastFetch.current = { point: ambulancePoint, at: now };
    let cancelled = false;
    fetchRoute(ambulancePoint, patient).then((r) => {
      if (cancelled) return;
      setRoute(r);
      onEta?.(r.durationSec, r.distanceKm);
    });
    return () => {
      cancelled = true;
    };
  }, [toPatient, ambulancePoint, patient, onEta]);

  if (!route) return null;
  return (
    <Polyline
      positions={route.points}
      pathOptions={{ color: '#283593', weight: 4, opacity: 0.85 }}
    />
  );
}
