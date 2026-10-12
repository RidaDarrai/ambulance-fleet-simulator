import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:latlong2/latlong.dart';

import 'app_repository.dart';
import 'mission_status.dart';
import 'models.dart';
import '../services/chat_service.dart';
import '../services/routing_service.dart';

/// Real data source backed by Firestore / Auth / RTDB.
///
/// It implements the same [AppRepository] contract the demo sim does, so the
/// screens are oblivious to the swap. Field names and collections match the
/// backend that `dispatcher_app` / `crew_app` already operate on:
///
///  * `ambulances/{id}`  — `plate`, `crewId`, `status:'active'`, `base{lat,lng}`
///  * `missions/{id}`    — `status`, `ambulanceId`, `location{lat,lng}`,
///                         `timeline{…}`, `hospitalId`, `patientId`,
///                         `patientPhone`, `medicalAttached`
///  * `patients/{uid}`   — medical profile (model-native shape)
///  * RTDB `positions/{id}` — live `{lat,lng}` per ambulance
///
/// The backend uses 8 mission statuses (`requested`, `assigned`, `accepted`,
/// `enRoute`, `onScene`, `transporting`, `atHospital`, `resolved`); the design
/// locks 7. This repository folds `assigned` + `accepted` → `dispatched` so the
/// UI never sees an eighth state (docs/design/firebase-backend-handoff.md §3).
class FirebaseRepository extends AppRepository {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  DatabaseReference get _positionsRef =>
      FirebaseDatabase.instance.ref('positions');

  // ── Data state ──────────────────────────────────────────────────────
  @override
  List<AmbulanceUnit> units = [];
  @override
  List<Incident> history = [];
  @override
  Incident? activeIncident;
  @override
  MedicalProfile medicalProfile = MedicalProfile();
  @override
  LatLng userLocation = kUserLocation;
  @override
  List<LatLng>? get activeRoute => _activeRouteStore;

  @override
  bool isAuthenticated = false;
  @override
  bool offline = false;

  @override
  bool fleetLoading = true;
  @override
  bool fleetError = false;
  @override
  DateTime lastFleetUpdate = DateTime.now();
  @override
  bool medicalLoading = false;

  @override
  bool simulateSubmitError = false; // demo-only toggles — inert here
  @override
  bool simulateSaveError = false;
  @override
  bool sendFailed = false;
  @override
  LatLng? lastRequestPickup;
  @override
  bool lastRequestMedical = false;

  // ── Internal wiring ─────────────────────────────────────────────────
  String? _activeMissionId; // Firestore doc we're currently streaming
  String? _lastGuestName; // remembered so a retry keeps guest callback
  String? _lastGuestPhone;
  final RoutingService _routing = RoutingService();
  final ChatService _chat = ChatService();
  List<LatLng>? _activeRouteStore; // OSRM route for the active mission
  LatLng? _routeStart; // unit position the current route was built from
  MissionStatus? _routeStatus; // status the current route was built for
  bool _routingInFlight = false;
  final Map<String, AmbulanceUnit> _fleetDocs = {}; // ambulanceId -> unit (base)
  final Map<String, LatLng> _positions = {}; // ambulanceId -> live position
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _fleetSub;
  StreamSubscription<DatabaseEvent>? _posSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _missionSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _historySub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _medicalSub;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  /// The one patient this repository is scoped to — set from [authStateChanges].
  String? get _uid => _auth.currentUser?.uid;

  FirebaseRepository() {
    _authSub = _auth.authStateChanges().listen(_onAuthChanged);
    _connSub = Connectivity().onConnectivityChanged.listen(_onConnectivity);
    _subscribeFleet();
    // Seed current auth state (auth may already be resolved).
    _onAuthChanged(_auth.currentUser);
  }

  // ── Auth ────────────────────────────────────────────────────────────
  void _onAuthChanged(User? user) {
    final was = isAuthenticated;
    isAuthenticated = user != null;
    if (was != isAuthenticated) {
      // Re-scope the patient streams (history + medical profile) to the uid.
      _subscribeMedical();
      _subscribeHistory();
      notifyListeners();
    }
  }

  @override
  void signIn() {
    // Phone sign-in is driven directly by the sign-in screen against
    // FirebaseAuth; `authStateChanges` flips `isAuthenticated` for us.
  }

  @override
  void signOut() {
    _activeMissionId = null;
    _missionSub?.cancel();
    _missionSub = null;
    activeIncident = null;
    _auth.signOut();
  }

  // ── Location & connectivity ─────────────────────────────────────────
  @override
  void setUserLocation(LatLng point) {
    userLocation = point;
    notifyListeners();
  }

  void _onConnectivity(List<ConnectivityResult> result) {
    final nowOffline = result.isEmpty || result.every((r) => r == ConnectivityResult.none);
    if (nowOffline != offline) {
      offline = nowOffline;
      notifyListeners();
    }
  }

  @override
  void setOffline(bool value) {
    offline = value;
    notifyListeners();
  }

  // ── Fleet (ambulances ⨯ RTDB positions) ─────────────────────────────
  void _subscribeFleet() {
    _fleetSub = _db
        .collection('ambulances')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .listen((snap) {
      _fleetDocs.clear();
      for (final d in snap.docs) {
        _fleetDocs[d.id] = AmbulanceUnit(
          id: d.id,
          callsign: (d.data()['plate'] as String?) ?? d.id,
          crewSize: 2,
          vehicleType: 'ALS',
          position: kUserLocation, // replaced once its RTDB position arrives
        );
      }
      _rebuildUnits();
    }, onError: (_) {
      fleetError = true;
      fleetLoading = false;
      notifyListeners();
    });

    _posSub = _positionsRef.onValue.listen((event) {
      _positions.clear();
      final value = event.snapshot.value;
      if (value is Map) {
        value.forEach((key, v) {
          if (v is Map && v['lat'] is num && v['lng'] is num) {
            _positions[key as String] = LatLng(
              (v['lat'] as num).toDouble(),
              (v['lng'] as num).toDouble(),
            );
          }
        });
      }
      _rebuildUnits();
    });
  }

  void _rebuildUnits() {
    final list = _fleetDocs.values.map((base) {
      final pos = _positions[base.id];
      if (pos != null) base.position = pos;
      return base;
    }).toList()
      ..sort((a, b) => a.callsign.compareTo(b.callsign));
    units = list;
    fleetLoading = false;
    fleetError = false;
    lastFleetUpdate = DateTime.now();
    notifyListeners();
    _refreshRoute(); // unit moved → re-route along streets when needed
  }

  @override
  void refreshFleet() {
    fleetLoading = true;
    fleetError = false;
    notifyListeners();
    // Streams are live; the next snapshot clears the skeleton. Refresh just
    // re-stamps freshness so the "Updated Xs ago" label resets immediately.
    lastFleetUpdate = DateTime.now();
  }

  @override
  void setFleetError(bool value) {
    fleetError = value;
    notifyListeners();
  }

  @override
  void setSimulateSubmitError(bool value) => simulateSubmitError = value;
  @override
  void setSimulateSaveError(bool value) => simulateSaveError = value;

  // ── Incident lifecycle ──────────────────────────────────────────────
  @override
  Future<void> triggerRequest(
      {LatLng? pickup,
      bool? medicalAttached,
      String? guestName,
      String? guestPhone}) async {
    if (activeIncident != null) return;
    lastRequestPickup = pickup ?? userLocation;
    if (medicalAttached != null) lastRequestMedical = medicalAttached;
    if (guestName != null && guestName.isNotEmpty) _lastGuestName = guestName;
    if (guestPhone != null && guestPhone.isNotEmpty) _lastGuestPhone = guestPhone;

    sendFailed = false;
    final point = lastRequestPickup!;
    // Optimistically surface a pending incident so the queued screen has
    // something to render while the write round-trips; the real doc replaces
    // it as soon as its first snapshot arrives.
    activeIncident = Incident(
      id: 'pending-write',
      pickup: point,
      hospital: kHospital,
      createdAt: DateTime.now(),
      status: MissionStatus.pending,
      medicalAttached: lastRequestMedical,
    );
    notifyListeners();
    try {
      final doc = await _db.collection('missions').add({
        'status': 'requested',
        'patientId': _uid,
        if (_lastGuestPhone != null) 'patientPhone': _lastGuestPhone,
        if (_lastGuestName != null) 'patientName': _lastGuestName,
        'medicalAttached': lastRequestMedical,
        'location': {'lat': point.latitude, 'lng': point.longitude},
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        // Nested map, NOT a flat 'timeline.requested' key: `.add()` treats dots
        // as literal characters, so a flat key would never land in the `timeline`
        // map the dispatcher/crew `update()` writes (and this adapter reads).
        'timeline': {'requested': FieldValue.serverTimestamp()},
      });
      _watchMission(doc.id);
    } catch (_) {
      activeIncident = null;
      sendFailed = true;
      notifyListeners();
    }
  }

  void _watchMission(String id) {
    _missionSub?.cancel();
    _activeMissionId = id;
    _missionSub = _db.collection('missions').doc(id).snapshots().listen(
      (snap) => _onMission(snap),
      onError: (_) {
        sendFailed = true;
        notifyListeners();
      },
    );
  }

  Future<void> _onMission(DocumentSnapshot<Map<String, dynamic>> snap) async {
    if (!snap.exists) return;
    final data = snap.data()!;
    final raw = (data['status'] as String?) ?? 'requested';

    // Backend-only states with no design equivalent.
    if (raw == 'cancelled') {
      activeIncident = null;
      _activeMissionId = null;
      _missionSub?.cancel();
      _missionSub = null;
      notifyListeners();
      return;
    }

    final status = mapBackendStatus(raw);
    final loc = data['location'];
    final pickup = loc is Map && loc['lat'] is num && loc['lng'] is num
        ? LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble())
        : userLocation;

    final incident = Incident(
      id: snap.id,
      pickup: pickup,
      hospital: await _resolveHospital(data['hospitalId'] as String?),
      createdAt: _ts(data['createdAt']) ?? DateTime.now(),
      status: status,
      medicalAttached: (data['medicalAttached'] as bool?) ?? false,
      unitId: data['ambulanceId'] as String?,
      unitCallsign: _callsign(data['ambulanceId'] as String?),
      etaSeconds: 0,
    );
    _applyTimeline(incident, data['timeline']);

    // Interim client ETA until the server-computed one lands (Phase 6).
    incident.etaSeconds = _estimateEta(incident, status);

    activeIncident = incident;
    if (status == MissionStatus.resolved && !history.any((h) => h.id == incident.id)) {
      history.insert(0, incident);
    }
    if (status == MissionStatus.resolved) _activeRouteStore = null;
    notifyListeners();
    _refreshRoute();
  }

  int _estimateEta(Incident inc, MissionStatus status) {
    if (inc.unitId == null) return 0;
    final unitPos = _positions[inc.unitId!];
    if (unitPos == null) return 0;
    final target = (status == MissionStatus.transporting ||
            status == MissionStatus.atHospital)
        ? inc.hospital
        : inc.pickup;
    final km = const Distance().as(LengthUnit.Kilometer, unitPos, target);
    return (km / 40 * 3600).round(); // 40 km/h interim assumption
  }

  /// Fetches (or refreshes) the OSRM street route for the active mission.
  /// Re-fetches only when the status/target changed or the assigned unit has
  /// moved meaningfully (~120 m) since the last fetch, so it doesn't hammer
  /// the routing server on every position tick. Falls back to a straight
  /// line (null) when there's no unit, no position, or the mission is done.
  Future<void> _refreshRoute() async {
    final inc = activeIncident;
    if (inc == null ||
        inc.unitId == null ||
        inc.status == MissionStatus.resolved ||
        inc.status == MissionStatus.onScene) {
      _activeRouteStore = null;
      return;
    }
    final unitPos = _positions[inc.unitId!];
    if (unitPos == null) {
      _activeRouteStore = null;
      return;
    }
    final target = (inc.status == MissionStatus.transporting ||
            inc.status == MissionStatus.atHospital)
        ? inc.hospital
        : inc.pickup;
    final moved = _routeStart == null ||
        const Distance().as(LengthUnit.Meter, _routeStart!, unitPos) > 120;
    final statusChanged = _routeStatus != inc.status;
    if (!moved && !statusChanged && _activeRouteStore != null) return;
    if (_routingInFlight) return;
    _routingInFlight = true;
    try {
      final r = await _routing.route(unitPos, target);
      _activeRouteStore = r.points.length >= 2 ? r.points : null;
      _routeStart = unitPos;
      _routeStatus = inc.status;
      notifyListeners();
    } finally {
      _routingInFlight = false;
    }
  }

  static const Map<String, MissionStatus> _timelineKeys = {
    'requested': MissionStatus.pending,
    'assigned': MissionStatus.dispatched,
    'accepted': MissionStatus.dispatched,
    'enRoute': MissionStatus.enRoute,
    'onScene': MissionStatus.onScene,
    'transporting': MissionStatus.transporting,
    'atHospital': MissionStatus.atHospital,
    'resolved': MissionStatus.resolved,
  };

  void _applyTimeline(Incident inc, dynamic timeline) {
    if (timeline is! Map) return;
    timeline.forEach((key, value) {
      final status = _timelineKeys[key as String?];
      final at = _ts(value);
      if (status != null && at != null) inc.statusTimes[status] = at;
    });
  }

  Future<LatLng> _resolveHospital(String? hospitalId) async {
    if (hospitalId == null) return kHospital;
    try {
      final snap = await _db.collection('hospitals').doc(hospitalId).get();
      final loc = snap.data()?['location'];
      if (loc is Map && loc['lat'] is num && loc['lng'] is num) {
        return LatLng((loc['lat'] as num).toDouble(),
            (loc['lng'] as num).toDouble());
      }
    } catch (_) {}
    return kHospital;
  }

  String? _callsign(String? ambulanceId) {
    if (ambulanceId == null) return null;
    return _fleetDocs[ambulanceId]?.callsign ?? ambulanceId;
  }

  static DateTime? _ts(dynamic v) =>
      v is Timestamp ? v.toDate() : null;

  @override
  Future<void> cancelRequest() async {
    final id = _activeMissionId;
    activeIncident = null;
    _activeMissionId = null;
    _missionSub?.cancel();
    _missionSub = null;
    sendFailed = false;
    _activeRouteStore = null;
    notifyListeners();
    if (id != null) {
      // Patients currently lack a direct update grant for status, so this
      // write is the interim path (rules are open in dev); the hardened path
      // is a callable Cloud Function (Phase 9).
      try {
        await _db.collection('missions').doc(id).update({
          'status': 'cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }
  }

  @override
  void clearActiveIncident() {
    _activeMissionId = null;
    _missionSub?.cancel();
    _missionSub = null;
    activeIncident = null;
    _activeRouteStore = null;
    notifyListeners();
  }

  // ── History (resolved missions for this patient) ────────────────────
  void _subscribeHistory() {
    _historySub?.cancel();
    final uid = _uid;
    if (uid == null) {
      history = [];
      return;
    }
    _historySub = _db
        .collection('missions')
        .where('patientId', isEqualTo: uid)
        .where('status', isEqualTo: 'resolved')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      history = snap.docs.map((d) {
        final data = d.data();
        final loc = data['location'];
        final pickup =
            loc is Map && loc['lat'] is num && loc['lng'] is num
                ? LatLng((loc['lat'] as num).toDouble(),
                    (loc['lng'] as num).toDouble())
                : kUserLocation;
        final inc = Incident(
          id: d.id,
          pickup: pickup,
          hospital: kHospital,
          createdAt: _ts(data['createdAt']) ?? DateTime.now(),
          status: MissionStatus.resolved,
          medicalAttached: (data['medicalAttached'] as bool?) ?? false,
          unitCallsign: _callsign(data['ambulanceId'] as String?),
        );
        _applyTimeline(inc, data['timeline']);
        return inc;
      }).toList();
      notifyListeners();
    }, onError: (_) {});
  }

  // ── Medical profile (patients/{uid}) ────────────────────────────────
  void _subscribeMedical() {
    _medicalSub?.cancel();
    final uid = _uid;
    if (uid == null) return;
    medicalLoading = true;
    _medicalSub = _db.collection('patients').doc(uid).snapshots().listen(
      (snap) {
        medicalLoading = false;
        if (!snap.exists) return;
        medicalProfile = _profileFrom(snap.data()!);
        notifyListeners();
      },
      onError: (_) {
        medicalLoading = false;
        notifyListeners();
      },
    );
  }

  MedicalProfile _profileFrom(Map<String, dynamic> data) {
    final contacts = <EmergencyContact>[];
    final rawContacts = data['contacts'];
    if (rawContacts is List) {
      for (final c in rawContacts) {
        if (c is Map) {
          contacts.add(EmergencyContact(
            id: (c['id'] as String?) ??
                DateTime.now().microsecondsSinceEpoch.toString(),
            name: (c['name'] as String?) ?? '',
            relationship: (c['relationship'] as String?) ?? '',
            phone: (c['phone'] as String?) ?? '',
          ));
        }
      }
    }
    return MedicalProfile(
      bloodType: data['bloodType'] as String?,
      allergies: List<String>.from(data['allergies'] as List? ?? const []),
      conditions: List<String>.from(data['conditions'] as List? ?? const []),
      contacts: contacts,
      lastUpdated: _ts(data['updatedAt']) ?? DateTime.now(),
    );
  }

  Future<void> _persistMedical() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db.collection('patients').doc(uid).set({
        'bloodType': medicalProfile.bloodType,
        'allergies': medicalProfile.allergies,
        'conditions': medicalProfile.conditions,
        'contacts': medicalProfile.contacts
            .map((c) => {
                  'id': c.id,
                  'name': c.name,
                  'relationship': c.relationship,
                  'phone': c.phone,
                })
            .toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      medicalProfile.pendingSync = false;
    } catch (_) {
      medicalProfile.pendingSync = offline;
    }
  }

  bool _finishMedicalEdit() {
    medicalProfile.lastUpdated = DateTime.now();
    medicalProfile.pendingSync = offline;
    _persistMedical();
    notifyListeners();
    return true;
  }

  @override
  bool setBloodType(String? value) {
    medicalProfile.bloodType = value;
    return _finishMedicalEdit();
  }

  @override
  bool setAllergies(List<String> value) {
    medicalProfile.allergies
      ..clear()
      ..addAll(value);
    return _finishMedicalEdit();
  }

  @override
  bool setConditions(List<String> value) {
    medicalProfile.conditions
      ..clear()
      ..addAll(value);
    return _finishMedicalEdit();
  }

  @override
  bool addContact(EmergencyContact contact) {
    medicalProfile.contacts.add(contact);
    return _finishMedicalEdit();
  }

  @override
  bool updateContact(EmergencyContact contact) => _finishMedicalEdit();

  @override
  bool removeContact(EmergencyContact contact) {
    medicalProfile.contacts.remove(contact);
    return _finishMedicalEdit();
  }

  @override
  void resetMedicalProfile() {
    medicalProfile
      ..bloodType = null
      ..allergies.clear()
      ..conditions.clear()
      ..contacts.clear();
    _persistMedical();
    notifyListeners();
  }

  // ── Crew chat ───────────────────────────────────────────────────────
  @override
  Stream<List<ChatMessage>> watchChat(String missionId) =>
      _chat.watch(missionId);

  @override
  Future<void> sendChat(String missionId, String text) =>
      _chat.send(missionId, text);

  @override
  void dispose() {
    _authSub?.cancel();
    _fleetSub?.cancel();
    _posSub?.cancel();
    _missionSub?.cancel();
    _historySub?.cancel();
    _medicalSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}
