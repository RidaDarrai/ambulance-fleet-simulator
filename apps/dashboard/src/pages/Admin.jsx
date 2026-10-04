import { useState } from 'react';

const TABS = ['Fleet', 'Users', 'Missions', 'Analytics'];

export default function Admin() {
  const [tab, setTab] = useState('Fleet');

  return (
    <div className="admin-layout">
      <nav className="tabs">
        {TABS.map((t) => (
          <button
            key={t}
            className={t === tab ? 'active' : ''}
            onClick={() => setTab(t)}
          >
            {t}
          </button>
        ))}
      </nav>
      <section className="tab-content">
        <h3>{tab}</h3>
        <p className="muted">Content arrives in M4 (tables, CRUD, analytics).</p>
      </section>
    </div>
  );
}
