import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:patient_app/services/routing_service.dart';

void main() {
  final routing = RoutingService();

  test('straightLine estimates duration at assumed speed', () {
    const from = LatLng(33.5731, -7.5898);
    const to = LatLng(33.6731, -7.5898); // ~11.1 km (0.1 deg latitude)
    final res = routing.straightLine(from, to, speedKmh: 40);
    expect(res.points, hasLength(2));
    expect(res.distanceKm, closeTo(11.1, 0.3));
    expect(res.duration.inMinutes, closeTo(16.7, 1.0));
  });

  test('straightLine with identical points is zero-distance', () {
    const p = LatLng(33.5731, -7.5898);
    final res = routing.straightLine(p, p);
    expect(res.distanceKm, 0);
    expect(res.duration, Duration.zero);
    expect(res.points, hasLength(2));
  });
}
