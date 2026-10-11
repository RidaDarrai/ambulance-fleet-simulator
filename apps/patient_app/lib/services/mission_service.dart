import 'package:cloud_firestore/cloud_firestore.dart';

class MissionService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<String> createRequest({
    required double lat,
    required double lng,
    String? patientId,
    String? phone,
  }) async {
    final doc = await _db.collection('missions').add({
      'status': 'requested',
      'patientId': patientId,
      if (phone != null && phone.isNotEmpty) 'patientPhone': phone,
      'location': {'lat': lat, 'lng': lng},
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      // Nested map (not a flat 'timeline.requested' key) so the timestamp lands
      // in the `timeline` sub-map that dispatch/crew `update()` writes into.
      'timeline': {'requested': FieldValue.serverTimestamp()},
    });
    return doc.id;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watch(String id) =>
      _db.collection('missions').doc(id).snapshots();

  Future<Map<String, dynamic>?> hospitalLocation(String id) async {
    final snap = await _db.collection('hospitals').doc(id).get();
    final loc = snap.data()?['location'];
    return loc is Map<String, dynamic> ? loc : null;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchFleet() => _db
      .collection('ambulances')
      .where('status', isEqualTo: 'active')
      .snapshots();
}

