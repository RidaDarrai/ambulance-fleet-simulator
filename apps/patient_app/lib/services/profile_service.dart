import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileService {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Stream<User?> get authChanges => _auth.authStateChanges();
  User? get current => _auth.currentUser;

  Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  Future<void> signUp(String email, String password) =>
      _auth.createUserWithEmailAndPassword(email: email, password: password);

  Future<void> signOut() => _auth.signOut();

  Future<void> saveProfile({
    required String bloodType,
    required String allergies,
    required String conditions,
    required String emergencyContact,
  }) async {
    final uid = _auth.currentUser!.uid;
    await _db.collection('patients').doc(uid).set({
      'bloodType': bloodType,
      'allergies': allergies,
      'conditions': conditions,
      'emergencyContact': emergencyContact,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> loadProfile() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final snap = await _db.collection('patients').doc(uid).get();
    return snap.data();
  }
}

