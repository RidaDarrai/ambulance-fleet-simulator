import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/mission_service.dart';
import '../services/profile_service.dart';
import 'fleet_map_screen.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  final _missions = MissionService();
  final _profile = ProfileService();

  String? _missionId;
  LatLng _picked = kCityCenter;
  bool _busy = false;

  Future<void> _useGps() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission denied');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      setState(() => _picked = LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not get GPS — long-press the map to pick a spot.'),
          ),
        );
      }
    }
  }

  Future<void> _panic() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send emergency request?'),
        content: Text(
          'Location: ${_picked.latitude.toStringAsFixed(4)}, '
          '${_picked.longitude.toStringAsFixed(4)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SEND'),
          ),
        ],
      ),
    );
    if (confirmed != true || _busy) return;
    setState(() => _busy = true);
    try {
      final id = await _missions.createRequest(
        lat: _picked.latitude,
        lng: _picked.longitude,
        patientId: _profile.current?.uid,
      );
      setState(() => _missionId = id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send request. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_missionId != null) {
      return TrackingView(
        missionId: _missionId!,
        onAbort: () => setState(() => _missionId = null),
      );
    }
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: _picked,
            initialZoom: 13,
            onLongPress: (_, point) => setState(() => _picked = point),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.ambulancesim.patient_app',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: _picked,
                  child: const Icon(Icons.location_on,
                      color: Colors.red, size: 40),
                ),
              ],
            ),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('© OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: Column(
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  minimumSize: const Size.fromHeight(64),
                  textStyle: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
                onPressed: _busy ? null : _panic,
                icon: const Icon(Icons.warning_amber_rounded, size: 32),
                label: Text(_busy ? 'SENDING…' : 'PANIC'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _useGps,
                icon: const Icon(Icons.my_location),
                label: const Text('Use my GPS location'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

const _statusLabels = {
  'requested': ('Waiting for dispatcher', Colors.orange),
  'assigned': ('Ambulance assigned', Colors.blueGrey),
  'accepted': ('Crew accepted', Colors.blue),
  'enRoute': ('En route to you', Colors.indigo),
  'onScene': ('Ambulance on scene', Colors.teal),
  'transporting': ('Transporting to hospital', Colors.purple),
  'atHospital': ('Arrived at hospital', Colors.green),
  'resolved': ('Mission completed', Colors.grey),
};

class TrackingView extends StatelessWidget {
  const TrackingView({super.key, required this.missionId, required this.onAbort});

  final String missionId;
  final VoidCallback onAbort;

  @override
  Widget build(BuildContext context) {
    final missions = MissionService();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: missions.watch(missionId),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final status = data['status'] as String? ?? 'requested';
        final (label, color) =
            _statusLabels[status] ?? ('Unknown', Colors.grey);
        final loc = data['location'] as Map<String, dynamic>? ?? {};
        final patientPoint = LatLng(
          (loc['lat'] as num?)?.toDouble() ?? kCityCenter.latitude,
          (loc['lng'] as num?)?.toDouble() ?? kCityCenter.longitude,
        );
        final ambulanceId = data['ambulanceId'] as String?;

        return Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    options:
                        MapOptions(initialCenter: patientPoint, initialZoom: 13),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.ambulancesim.patient_app',
                      ),
                      MarkerLayer(markers: [
                        Marker(
                          point: patientPoint,
                          child: const Icon(Icons.person_pin,
                              color: Colors.red, size: 40),
                        ),
                      ]),
                      if (ambulanceId != null)
                        _AmbulanceLiveLayer(ambulanceId: ambulanceId),
                      const RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution('© OpenStreetMap contributors'),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(label,
                                style:
                                    const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: onAbort,
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel / back'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AmbulanceLiveLayer extends StatelessWidget {
  const _AmbulanceLiveLayer({required this.ambulanceId});

  final String ambulanceId;

  Marker _at(LatLng point) {
    return Marker(
      point: point,
      width: 120,
      height: 44,
      child: const Column(
        children: [
          Icon(Icons.local_hospital, color: Colors.blue, size: 30),
          Text('Ambulance',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseDatabase.instance.ref('positions/$ambulanceId');
    return StreamBuilder<DatabaseEvent>(
      stream: ref.onValue,
      builder: (context, snapshot) {
        LatLng? point;
        final value = snapshot.data?.snapshot.value;
        if (value is Map && value['lat'] is num && value['lng'] is num) {
          point = LatLng(
            (value['lat'] as num).toDouble(),
            (value['lng'] as num).toDouble(),
          );
        }
        if (point != null) {
          return MarkerLayer(markers: [_at(point)]);
        }
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('ambulances')
              .doc(ambulanceId)
              .get(),
          builder: (context, snap) {
            final base = snap.data?.data()?['base'] as Map<String, dynamic>?;
            if (base == null) return const MarkerLayer(markers: []);
            return MarkerLayer(markers: [
              _at(LatLng(
                (base['lat'] as num).toDouble(),
                (base['lng'] as num).toDouble(),
              )),
            ]);
          },
        );
      },
    );
  }
}
