import 'package:firebase_database/firebase_database.dart';
import 'package:latlong2/latlong.dart';

class PositionService {
  /// All live ambulance positions: ambulanceId -> point.
  Stream<Map<String, LatLng>> watchAll() {
    final ref = FirebaseDatabase.instance.ref('positions');
    return ref.onValue.map((event) {
      final out = <String, LatLng>{};
      final value = event.snapshot.value;
      if (value is Map) {
        value.forEach((key, v) {
          if (v is Map && v['lat'] is num && v['lng'] is num) {
            out[key as String] = LatLng(
              (v['lat'] as num).toDouble(),
              (v['lng'] as num).toDouble(),
            );
          }
        });
      }
      return out;
    });
  }

  /// Single ambulance position, or null when offline.
  Stream<LatLng?> watchOne(String ambulanceId) {
    final ref = FirebaseDatabase.instance.ref('positions/$ambulanceId');
    return ref.onValue.map((event) {
      final v = event.snapshot.value;
      if (v is Map && v['lat'] is num && v['lng'] is num) {
        return LatLng((v['lat'] as num).toDouble(), (v['lng'] as num).toDouble());
      }
      return null;
    });
  }
}
