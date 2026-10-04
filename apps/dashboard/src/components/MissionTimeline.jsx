const STEPS = [
  ['assigned', 'Ambulance assigned'],
  ['accepted', 'Crew accepted'],
  ['enRoute', 'En route to patient'],
  ['onScene', 'On scene'],
  ['transporting', 'Transporting'],
  ['atHospital', 'Arrived at hospital'],
  ['resolved', 'Completed'],
];

function formatTime(ts) {
  const millis = ts?.toMillis?.();
  if (!millis) return '';
  return new Date(millis).toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit',
  });
}

export default function MissionTimeline({ mission }) {
  const tl = mission.timeline ?? {};
  return (
    <ul className="timeline">
      {STEPS.map(([key, label]) => {
        const at = tl[key];
        const done = Boolean(at);
        const current = mission.status === key;
        return (
          <li
            key={key}
            className={`${done ? 'done' : 'pending'} ${
              current ? 'current' : ''
            }`}
          >
            <span className="tl-dot" />
            <span className="tl-label">{label}</span>
            <span className="tl-time">{done ? formatTime(at) : '—'}</span>
          </li>
        );
      })}
    </ul>
  );
}
