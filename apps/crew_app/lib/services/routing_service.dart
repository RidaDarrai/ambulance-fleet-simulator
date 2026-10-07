import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteResult {
  const RouteResult({
    required this.points,
    required this.duration,
    required this.distanceKm,
  });

  final List<LatLng> points;
  final Duration duration;
  final double distanceKm;
}

class RoutingService {
  /// OSRM route with graceful straight-line fallback (40 km/h assumption).
  Future<RouteResult> route(LatLng from, LatLng to) async {
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final routes = json['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final r = routes.first as Map<String, dynamic>;
          final geometry = r['geometry'] as Map<String, dynamic>;
          final coords = geometry['coordinates'] as List;
          final points = coords
              .map((c) => LatLng(
                    (c[1] as num).toDouble(),
                    (c[0] as num).toDouble(),
                  ))
              .toList();
          if (points.length >= 2) {
            return RouteResult(
              points: points,
              duration: Duration(seconds: (r['duration'] as num).round()),
              distanceKm: (r['distance'] as num) / 1000,
            );
          }
        }
      }
    } catch (_) {
      // fall through to straight line
    }
    return straightLine(from, to);
  }

  RouteResult straightLine(LatLng from, LatLng to, {double speedKmh = 40}) {
    final km = const Distance().as(LengthUnit.Kilometer, from, to);
    final hours = km / speedKmh;
    return RouteResult(
      points: [from, to],
      duration: Duration(milliseconds: (hours * 3600 * 1000).round()),
      distanceKm: km,
    );
  }
}
