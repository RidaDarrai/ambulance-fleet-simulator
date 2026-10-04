import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/mission_service.dart';

const kCityCenter = LatLng(33.5731, -7.5898);

class FleetMapScreen extends StatelessWidget {
  FleetMapScreen({super.key});

  final _service = MissionService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _service.watchFleet(),
      builder: (context, snapshot) {
        final markers = <Marker>[];
        for (final d in snapshot.data?.docs ?? []) {
          final base = d.data()['base'] as Map<String, dynamic>?;
          if (base == null) continue;
          markers.add(
            Marker(
              point: LatLng(
                (base['lat'] as num).toDouble(),
                (base['lng'] as num).toDouble(),
              ),
              width: 120,
              height: 44,
              child: const Column(
                children: [
                  Icon(Icons.local_hospital, color: Colors.blue, size: 30),
                  Text(
                    'Ambulance',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
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
  }
}
