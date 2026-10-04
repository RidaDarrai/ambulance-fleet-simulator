import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/chat_service.dart';
import '../services/contact_service.dart';
import '../services/mission_service.dart';
import '../services/position_service.dart';
import '../services/profile_service.dart';
import '../services/routing_service.dart';
import '../widgets/chat_sheet.dart';
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

class TrackingView extends StatefulWidget {
  const TrackingView({super.key, required this.missionId, required this.onAbort});

  final String missionId;
  final VoidCallback onAbort;

  @override
  State<TrackingView> createState() => _TrackingViewState();
}

class _TrackingViewState extends State<TrackingView> {
  final missions = MissionService();
  final chat = ChatService();
  Duration? _eta;
  int _total = 0;
  int _lastSeen = 0;

  void _onEta(Duration? eta) {
    if (!mounted || _eta == eta) return;
    setState(() => _eta = eta);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: missions.watch(widget.missionId),
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
                        _RouteLayer(
                          patientPoint: patientPoint,
                          ambulanceId: ambulanceId,
                          onEta: _onEta,
                        ),
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
                            if (_eta != null &&
                                const {'assigned', 'accepted', 'enRoute'}
                                    .contains(status))
                              Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: Text(
                                  _eta!.inMinutes < 1
                                      ? '· ETA <1 min'
                                      : '· ETA ~${_eta!.inMinutes} min',
                                  style: const TextStyle(
                                    color: Colors.indigo,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
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
                  StreamBuilder<int>(
                    stream: chat.watchCount(widget.missionId),
                    builder: (context, snap) {
                      _total = snap.data ?? 0;
                      final unread =
                          (_total - _lastSeen).clamp(0, 1 << 30);
                      return FilledButton.tonalIcon(
                        onPressed: () {
                          ChatSheet.open(
                            context,
                            missionId: widget.missionId,
                            title: 'Message dispatch & crew',
                          ).whenComplete(() {
                            if (mounted) setState(() => _lastSeen = _total);
                          });
                        },
                        icon: Badge(
                          isLabelVisible: unread > 0,
                          label: Text('$unread'),
                          child: const Icon(Icons.chat_bubble_outline),
                        ),
                        label: const Text('Chat'),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: () => launchCall(kDispatchHotline),
                    icon: const Icon(Icons.call),
                    label: const Text('Call'),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: widget.onAbort,
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

class _RouteLayer extends StatefulWidget {
  const _RouteLayer({
    required this.patientPoint,
    required this.ambulanceId,
    required this.onEta,
  });

  final LatLng patientPoint;
  final String ambulanceId;
  final void Function(Duration?) onEta;

  @override
  State<_RouteLayer> createState() => _RouteLayerState();
}

class _RouteLayerState extends State<_RouteLayer> {
  final _routing = RoutingService();
  final _positions = PositionService();
  StreamSubscription<LatLng?>? _sub;
  List<LatLng> _line = const [];
  LatLng? _lastFetch;
  DateTime _lastFetchAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _sub = _positions.watchOne(widget.ambulanceId).listen(_onPosition);
  }

  @override
  void didUpdateWidget(covariant _RouteLayer old) {
    super.didUpdateWidget(old);
    if (old.ambulanceId != widget.ambulanceId) {
      _sub?.cancel();
      _sub = _positions.watchOne(widget.ambulanceId).listen(_onPosition);
    } else if (old.patientPoint != widget.patientPoint) {
      _lastFetchAt = DateTime.fromMillisecondsSinceEpoch(0);
      final from = _lastFetch;
      if (from != null) _fetch(from);
    }
  }

  Future<void> _onPosition(LatLng? pos) async {
    if (pos == null) return;
    final now = DateTime.now();
    final movedKm = _lastFetch == null
        ? double.infinity
        : const Distance().as(LengthUnit.Kilometer, _lastFetch!, pos);
    if (movedKm < 0.05 || now.difference(_lastFetchAt).inSeconds < 3) return;
    await _fetch(pos);
  }

  Future<void> _fetch(LatLng from) async {
    if (_fetching) return;
    _fetching = true;
    _lastFetch = from;
    _lastFetchAt = DateTime.now();
    try {
      final res = await _routing.route(from, widget.patientPoint);
      if (!mounted) return;
      setState(() => _line = res.points);
      widget.onEta(res.duration);
    } finally {
      _fetching = false;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_line.length < 2) return PolylineLayer<Object>(polylines: const []);
    return PolylineLayer(polylines: [
      Polyline(points: _line, strokeWidth: 4.5, color: Colors.indigo),
    ]);
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
