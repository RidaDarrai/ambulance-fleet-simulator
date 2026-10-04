import 'package:firebase_database/firebase_database.dart';
import 'package:latlong2/latlong.dart';

class PositionService {
  /// Live position for one ambulance, or null when offline.
  Stream<LatLng?> watchOne(String ambulanceId) {
    final ref = FirebaseDatabase.instance.ref('positions/$ambulanceId');
    return ref.onValue.map((event) {
      final v = event.snapshot.value;
      if (v is Map && v['lat'] is num && v['lng'] is num) {
        return LatLng(
          (v['lat'] as num).toDouble(),
          (v['lng'] as num).toDouble(),
        );
      }
      return null;
    });
  }
}
