import { initializeApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';
import { getDatabase } from 'firebase/database';

const firebaseConfig = {
  apiKey: 'AIzaSyCgJPfBzOEitO945KNS9sWrPswoiErfNSc',
  authDomain: 'ambulance-dispatch-sim.firebaseapp.com',
  appId: '1:823967188310:web:8cd821eb79a90f71db82f7',
  messagingSenderId: '823967188310',
  projectId: 'ambulance-dispatch-sim',
  storageBucket: 'ambulance-dispatch-sim.firebasestorage.app',
};

export const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app);
export const rtdb = getDatabase(app);
