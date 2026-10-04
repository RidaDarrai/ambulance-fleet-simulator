import { useEffect, useState } from 'react';
import {
  BrowserRouter,
  Routes,
  Route,
  Navigate,
} from 'react-router-dom';
import { onAuthStateChanged, signOut } from 'firebase/auth';
import { auth } from './lib/firebase';
import Login from './pages/Login';
import Dispatcher from './pages/Dispatcher';
import Admin from './pages/Admin';
import './App.css';

export default function App() {
  const [user, setUser] = useState(null);
  const [role, setRole] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, async (u) => {
      setUser(u);
      if (u) {
        const token = await u.getIdTokenResult();
        setRole(token.claims.role || null);
      } else {
        setRole(null);
      }
      setLoading(false);
    });
    return unsub;
  }, []);

  if (loading) return <div className="center">Loading…</div>;

  const home = role === 'admin' ? '/admin' : role === 'dispatcher' ? '/dispatcher' : '/login';

  return (
    <BrowserRouter>
      {user && (
        <header className="topbar">
          <span className="brand">Ambulance Dispatch</span>
          <span className="who">{user.email} ({role || 'no role'})</span>
          <button onClick={() => signOut(auth)}>Sign out</button>
        </header>
      )}
      <Routes>
        <Route
          path="/login"
          element={user ? <Navigate to={home} replace /> : <Login />}
        />
        <Route
          path="/dispatcher"
          element={
            user && role === 'dispatcher' ? (
              <Dispatcher />
            ) : (
              <Denied user={user} role={role} />
            )
          }
        />
        <Route
          path="/admin"
          element={
            user && role === 'admin' ? <Admin /> : <Denied user={user} role={role} />
          }
        />
        <Route path="*" element={<Navigate to={user ? home : '/login'} replace />} />
      </Routes>
    </BrowserRouter>
  );
}

function Denied({ user, role }) {
  return (
    <div className="center">
      <p>{!user ? 'Please sign in.' : `Your account has role "${role ?? 'none'}" — access denied.`}</p>
      {user && <button onClick={() => signOut(auth)}>Sign out</button>}
    </div>
  );
}
