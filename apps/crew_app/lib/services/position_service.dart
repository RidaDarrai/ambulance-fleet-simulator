import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class PositionService {
  StreamSubscription<Position>? _uploadSub;

  /// Live position for one ambulance, or null when offline (read side —
  /// used by dispatch views; the crew's own position is the upload below).
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

  /// Check (and optionally prompt for) the OS location permission.
  /// [prompt] false = silent check only (re-check paths never re-prompt).
  static Future<bool> ensurePermission({bool prompt = true}) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && prompt) {
        permission = await Geolocator.requestPermission();
      }
      return permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever;
    } catch (_) {
      return false; // web prompt dismissed / unsupported platform
    }
  }

  /// Upload device fixes to RTDB `positions/{ambulanceId}` while duty is on
  /// (rules: `auth.token.role === 'crew'`). The payload mirrors the backend
  /// contract exactly (`scripts/gps-sim.mjs` + `functions.computeServerEta`):
  /// `{lat, lng, speed (km/h), updatedAt (epoch ms)}`.
  ///
  /// Returns false when permission is unavailable (caller surfaces the
  /// denied banner); true once the stream is running.
  Future<bool> startUpload(
    String ambulanceId, {
    required void Function(LatLng point) onFix,
    required void Function() onError,
  }) async {
    if (ambulanceId.isEmpty) return false;
    if (!await ensurePermission()) return false;
    stopUpload();

    final ref = FirebaseDatabase.instance.ref('positions/$ambulanceId');
    _uploadSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10, // ~10 m of travel between fixes (battery)
      ),
    ).listen(
      (pos) {
        final point = LatLng(pos.latitude, pos.longitude);
        onFix(point);
        // Fire-and-forget: RTDB queues nothing, but a dropped write just
        // leaves the previous fix (updatedAt ages → dispatch sees staleness).
        ref.set({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'speed': double.parse((pos.speed * 3.6).toStringAsFixed(1)),
          'updatedAt': ServerValue.timestamp,
        }).catchError((Object _) {});
      },
      onError: (Object _) => onError(), // GPS signal lost / services off
    );
    return true;
  }

  void stopUpload() {
    _uploadSub?.cancel();
    _uploadSub = null;
  }
}
