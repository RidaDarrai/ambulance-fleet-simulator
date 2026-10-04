import { useEffect, useRef, useState } from 'react';
import {
  addDoc,
  collection,
  limit,
  onSnapshot,
  orderBy,
  query,
  serverTimestamp,
} from 'firebase/firestore';
import { db } from '../lib/firebase';

const roleLabel = {
  patient: 'Patient',
  dispatcher: 'Dispatch',
  crew: 'Crew',
};

export default function ChatPanel({ missionId, myRole }) {
  const [messages, setMessages] = useState([]);
  const [draft, setDraft] = useState('');
  const endRef = useRef(null);

  useEffect(() => {
    const q = query(
      collection(db, 'missions', missionId, 'messages'),
      orderBy('at', 'desc'),
      limit(100)
    );
    const unsub = onSnapshot(
      q,
      (snap) => setMessages(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      (err) => console.error('chat:', err)
    );
    return unsub;
  }, [missionId]);

  useEffect(() => {
    endRef.current?.scrollIntoView({ block: 'end' });
  }, [messages]);

  async function send(e) {
    e.preventDefault();
    const text = draft.trim();
    if (!text) return;
    setDraft('');
    await addDoc(collection(db, 'missions', missionId, 'messages'), {
      text,
      senderRole: myRole,
      at: serverTimestamp(),
    });
  }

  return (
    <div className="chat-panel">
      <div className="chat-log">
        {messages.length === 0 && (
          <p className="muted">No messages yet.</p>
        )}
        {[...messages].reverse().map((m) => (
          <div
            key={m.id}
            className={`chat-msg ${m.senderRole === myRole ? 'mine' : ''}`}
          >
            <span className="chat-role">
              {roleLabel[m.senderRole] ?? m.senderRole}
            </span>
            <span>{m.text}</span>
          </div>
        ))}
        <div ref={endRef} />
      </div>
      <form className="chat-form" onSubmit={send}>
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder="Message the patient…"
        />
        <button type="submit" disabled={!draft.trim()}>
          Send
        </button>
      </form>
    </div>
  );
}
