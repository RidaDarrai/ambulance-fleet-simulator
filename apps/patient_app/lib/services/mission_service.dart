import 'package:cloud_firestore/cloud_firestore.dart';

class MissionService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<String> createRequest({
    required double lat,
    required double lng,
    String? patientId,
  }) async {
    final doc = await _db.collection('missions').add({
      'status': 'requested',
      'patientId': patientId,
      'location': {'lat': lat, 'lng': lng},
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'timeline.requested': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watch(String id) =>
      _db.collection('missions').doc(id).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchFleet() => _db
      .collection('ambulances')
      .where('status', isEqualTo: 'active')
      .snapshots();
}

