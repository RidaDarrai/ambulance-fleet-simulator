import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/contact_service.dart';
import '../services/crew_service.dart';
import '../services/position_service.dart';

const kCityCenter = LatLng(33.5731, -7.5898);

class OpsScreen extends StatefulWidget {
  const OpsScreen({super.key, required this.ambulanceId});

  final String ambulanceId;

  @override
  State<OpsScreen> createState() => _OpsScreenState();
}

class _OpsScreenState extends State<OpsScreen> {
  final _service = CrewService();
  Map<String, dynamic>? _ambulance;
  LatLng _center = kCityCenter;

  @override
  void initState() {
    super.initState();
    _loadAmbulance();
  }

  Future<void> _loadAmbulance() async {
    final data = await _service.ambulance(widget.ambulanceId);
    if (data == null) return;
    final base = data['base'] as Map<String, dynamic>?;
    setState(() {
      _ambulance = data;
      if (base != null) {
        _center = LatLng(
          (base['lat'] as num).toDouble(),
          (base['lng'] as num).toDouble(),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _service.watchMissionsFor(widget.ambulanceId),
      builder: (context, snapshot) {
        QueryDocumentSnapshot<Map<String, dynamic>>? assigned;
        for (final d in snapshot.data?.docs ?? []) {
          if (d.data()['status'] == 'assigned') assigned = d;
        }
        return Column(
          children: [
            if (assigned != null) _incomingBanner(assigned),
            Expanded(
              child: FlutterMap(
                options: MapOptions(initialCenter: _center, initialZoom: 13),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.ambulancesim.crew_app',
                  ),
                  _LivePositionLayer(
                    ambulanceId: widget.ambulanceId,
                    fallback: _center,
                  ),
                  const RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution('© OpenStreetMap contributors'),
                    ],
                  ),
                ],
              ),
            ),
            if (_ambulance != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        '${_ambulance!['plate'] ?? ''} — '
                        'status: ${_ambulance!['status'] ?? ''}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => launchCall(kDispatchHotline),
                      icon: const Icon(Icons.call),
                      label: const Text('Dispatch'),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _incomingBanner(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final loc = data['location'] as Map<String, dynamic>? ?? {};
    return Container(
      width: double.infinity,
      color: Colors.orange.shade100,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('INCOMING JOB',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.orange.shade900)),
          Text(
            'Patient at ${loc['lat'] ?? '?'}, ${loc['lng'] ?? '?'}',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                onPressed: () => _service.accept(doc.id),
                child: const Text('Accept'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => _service.reject(doc.id),
                child: const Text('Reject'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LivePositionLayer extends StatelessWidget {
  _LivePositionLayer({
    required this.ambulanceId,
    required this.fallback,
  });

  final String ambulanceId;
  final LatLng fallback;
  final _positions = PositionService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LatLng?>(
      stream: _positions.watchOne(ambulanceId),
      builder: (context, snapshot) {
        return MarkerLayer(markers: [
          Marker(
            point: snapshot.data ?? fallback,
            child: const Icon(Icons.local_hospital,
                color: Colors.blue, size: 36),
          ),
        ]);
      },
    );
  }
}
