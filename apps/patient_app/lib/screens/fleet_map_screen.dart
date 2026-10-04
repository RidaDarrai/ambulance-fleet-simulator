import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/mission_service.dart';
import '../services/position_service.dart';

const kCityCenter = LatLng(33.5731, -7.5898);

class FleetMapScreen extends StatelessWidget {
  FleetMapScreen({super.key});

  final _service = MissionService();
  final _positions = PositionService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _service.watchFleet(),
      builder: (context, fleetSnap) {
        return StreamBuilder<Map<String, LatLng>>(
          stream: _positions.watchAll(),
          builder: (context, posSnap) {
            final positions = posSnap.data ?? {};
            final markers = <Marker>[];
            for (final d in fleetSnap.data?.docs ?? []) {
              final data = d.data();
              final base = data['base'] as Map<String, dynamic>?;
              final point = positions[d.id] ??
                  (base == null
                      ? null
                      : LatLng(
                          (base['lat'] as num).toDouble(),
                          (base['lng'] as num).toDouble(),
                        ));
              if (point == null) continue;
              markers.add(
                Marker(
                  point: point,
                  width: 120,
                  height: 44,
                  child: Column(
                    children: [
                      Icon(
                        Icons.local_hospital,
                        color: positions.containsKey(d.id)
                            ? Colors.blue
                            : Colors.blueGrey,
                        size: 30,
                      ),
                      Text(
                        data['plate'] as String? ?? 'Ambulance',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              );
            }
            return FlutterMap(
              options: MapOptions(initialCenter: kCityCenter, initialZoom: 12),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.ambulancesim.patient_app',
                ),
                MarkerLayer(markers: markers),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('© OpenStreetMap contributors'),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}
