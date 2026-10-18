import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Driving-route lookup for the demo (design repo only).
///
/// The real app routes through the backend's OSRM service (ground truth);
/// this demo talks to the public OSRM demo server directly so the polyline
/// follows actual roads. Any failure falls back to a straight line — the
/// deck must never depend on the network for its geometry.
class RouteService {
  /// Public demo instance — fine for design review, NOT for production.
  static final Uri _base =
      Uri.parse('https://router.project-osrm.org/route/v1/driving/');

  /// OSRM road geometry [from] → [to], or null when unavailable.
  /// GeoJSON coordinates are [lon, lat]; we flip them to [lat, lon].
  static Future<List<LatLng>?> drivingRoute(LatLng from, LatLng to) async {
    final uri = Uri.parse(
      '$_base${from.longitude},${from.latitude};'
      '${to.longitude},${to.latitude}'
      '?overview=full&geometries=geojson',
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = json['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return null;
      final geometry =
          (routes.first as Map<String, dynamic>)['geometry'] as Map<String, dynamic>?;
      final coords = geometry?['coordinates'] as List<dynamic>?;
      if (coords == null || coords.length < 2) return null;
      final points = coords
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      return points;
    } catch (_) {
      return null; // offline / rate-limited → straight-line fallback
    }
  }

  // ── Geometry helpers ─────────────────────────────────────────────────

  static const _distance = Distance();

  /// Road distance in km along [route].
  static double totalKm(List<LatLng> route) {
    var km = 0.0;
    for (var i = 1; i < route.length; i++) {
      km += _distance.as(LengthUnit.Kilometer, route[i - 1], route[i]);
    }
    return km;
  }

  /// Point at [progress] (0..1) along [route], interpolating the segment
  /// it lands in. Precompute nothing: called at 1 Hz on ~500-point routes.
  static LatLng pointAlong(List<LatLng> route, double progress) {
    if (route.length < 2) return route.first;
    final p = progress.clamp(0.0, 1.0);
    final target = totalKm(route) * p;
    var walked = 0.0;
    for (var i = 1; i < route.length; i++) {
      final seg = _distance.as(LengthUnit.Kilometer, route[i - 1], route[i]);
      if (walked + seg >= target || i == route.length - 1) {
        final t = seg == 0 ? 1.0 : ((target - walked) / seg).clamp(0.0, 1.0);
        return LatLng(
          route[i - 1].latitude + (route[i].latitude - route[i - 1].latitude) * t,
          route[i - 1].longitude +
              (route[i].longitude - route[i - 1].longitude) * t,
        );
      }
      walked += seg;
    }
    return route.last;
  }
}
