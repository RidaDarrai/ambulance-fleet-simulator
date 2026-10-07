import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/contact_service.dart';
import '../services/crew_service.dart';
import '../services/position_service.dart';
import '../services/routing_service.dart';

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
        QueryDocumentSnapshot<Map<String, dynamic>>? active;
        for (final d in snapshot.data?.docs ?? []) {
          final s = d.data()['status'];
          if (s == 'assigned') assigned = d;
          if (s != null && activeStatuses.contains(s)) active = d;
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
                  if (active != null)
                    _MissionRouteLayer(
                      key: ValueKey(active.id),
                      ambulanceId: widget.ambulanceId,
                      mission: active.data(),
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

class _MissionRouteLayer extends StatefulWidget {
  const _MissionRouteLayer({
    super.key,
    required this.ambulanceId,
    required this.mission,
  });

  final String ambulanceId;
  final Map<String, dynamic> mission;

  @override
  State<_MissionRouteLayer> createState() => _MissionRouteLayerState();
}

class _MissionRouteLayerState extends State<_MissionRouteLayer> {
  final _routing = RoutingService();
  final _positions = PositionService();
  final _crew = CrewService();
  StreamSubscription<LatLng?>? _sub;
  List<LatLng> _line = const [];
  LatLng? _lastFetch;
  DateTime _lastFetchAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _busy = false;
  String? _targetKey;
  LatLng? _cachedTarget;

  @override
  void initState() {
    super.initState();
    _sub = _positions.watchOne(widget.ambulanceId).listen(_onPosition);
  }

  @override
  void didUpdateWidget(covariant _MissionRouteLayer old) {
    super.didUpdateWidget(old);
    _targetKey = null; // status/hospital changed — re-resolve target
    if (_lastFetch != null) _refresh(_lastFetch!, force: true);
  }

  String get _key =>
      '${widget.mission['status']}|${widget.mission['hospitalId'] ?? ''}';

  Future<LatLng?> _resolveTarget() async {
    final status = widget.mission['status'];
    if (['assigned', 'accepted', 'enRoute'].contains(status)) {
      final loc = widget.mission['location'];
      if (loc is Map && loc['lat'] is num && loc['lng'] is num) {
        return LatLng(
          (loc['lat'] as num).toDouble(),
          (loc['lng'] as num).toDouble(),
        );
      }
    }
    if (['onScene', 'transporting', 'atHospital'].contains(status)) {
      final hid = widget.mission['hospitalId'];
      if (hid is String && hid.isNotEmpty) {
        final loc = await _crew.hospitalLocation(hid);
        if (loc != null && loc['lat'] is num && loc['lng'] is num) {
          return LatLng(
            (loc['lat'] as num).toDouble(),
            (loc['lng'] as num).toDouble(),
          );
        }
      }
    }
    return null;
  }

  Future<void> _onPosition(LatLng? pos) async {
    if (pos == null) return;
    final now = DateTime.now();
    final movedKm = _lastFetch == null
        ? double.infinity
        : const Distance().as(LengthUnit.Kilometer, _lastFetch!, pos);
    if (movedKm < 0.05 || now.difference(_lastFetchAt).inSeconds < 3) return;
    await _refresh(pos);
  }

  Future<void> _refresh(LatLng from, {bool force = false}) async {
    if (_busy) return;
    _busy = true;
    try {
      if (force || _targetKey != _key) {
        _cachedTarget = await _resolveTarget();
        _targetKey = _key;
      }
      final target = _cachedTarget;
      if (!mounted || target == null) {
        if (mounted && _line.isNotEmpty) setState(() => _line = const []);
        return;
      }
      _lastFetch = from;
      _lastFetchAt = DateTime.now();
      final res = await _routing.route(from, target);
      if (!mounted) return;
      setState(() => _line = res.points);
    } finally {
      _busy = false;
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
