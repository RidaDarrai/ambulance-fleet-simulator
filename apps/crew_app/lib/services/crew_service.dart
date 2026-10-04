import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const activeStatuses = [
  'assigned',
  'accepted',
  'enRoute',
  'onScene',
  'transporting',
  'atHospital',
];

const statusLabels = {
  'assigned': 'Incoming job',
  'accepted': 'Accepted — ready',
  'enRoute': 'En route to patient',
  'onScene': 'On scene',
  'transporting': 'Transporting to hospital',
  'atHospital': 'At hospital',
  'resolved': 'Completed',
};

class CrewService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  Stream<User?> get authChanges => _auth.authStateChanges();

  Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  Future<void> signOut() => _auth.signOut();

  Future<String?> myAmbulanceId(String uid) async {
    final snap = await _db
        .collection('ambulances')
        .where('crewId', isEqualTo: uid)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return snap.docs.first.id;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMissionsFor(
          String ambulanceId) =>
      _db
          .collection('missions')
          .where('ambulanceId', isEqualTo: ambulanceId)
          .snapshots();

  Future<Map<String, dynamic>?> ambulance(String id) async {
    final snap = await _db.collection('ambulances').doc(id).get();
    return snap.data();
  }

  Future<void> accept(String missionId) => _update(missionId, {
        'status': 'accepted',
        'timeline.accepted': FieldValue.serverTimestamp(),
      });

  Future<void> reject(String missionId) => _update(missionId, {
        'status': 'requested',
        'ambulanceId': null,
      });

  Future<void> advance(String missionId, String status) =>
      _update(missionId, {
        'status': status,
        'timeline.$status': FieldValue.serverTimestamp(),
      });

  Future<void> setHospital(String missionId, String hospitalId) =>
      _update(missionId, {'hospitalId': hospitalId});

  Future<void> _update(String missionId, Map<String, dynamic> data) {
    data['updatedAt'] = FieldValue.serverTimestamp();
    return _db.collection('missions').doc(missionId).update(data);
  }

  Future<Map<String, dynamic>?> patientProfile(String? uid) async {
    if (uid == null) return null;
    final snap = await _db.collection('patients').doc(uid).get();
    return snap.data();
  }

  Future<List<Map<String, String>>> hospitals() async {
    final snap = await _db.collection('hospitals').get();
    return snap.docs
        .map((d) => {'id': d.id, 'name': d.data()['name'] as String? ?? ''})
        .toList();
  }
}

