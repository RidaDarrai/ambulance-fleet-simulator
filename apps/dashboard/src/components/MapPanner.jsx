import { useEffect } from 'react';
import { useMap } from 'react-leaflet';

export default function MapPanner({ lat, lng }) {
  const map = useMap();
  useEffect(() => {
    if (typeof lat === 'number' && typeof lng === 'number') {
      map.setView([lat, lng], 14);
    }
  }, [map, lat, lng]);
  return null;
}
