import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../services/crew_service.dart';
import '../services/position_service.dart';
import 'crew_repository.dart';
import 'mission_status.dart';
import 'models.dart';
import 'route_service.dart';

/// Real backend behind the [CrewRepository] seam — Firestore / Auth / RTDB,
/// the crew counterpart to patient_app's `FirebaseRepository`.
///
/// Built in phases (see the wiring plan); members not yet backed by the
/// backend return safe inert defaults so no screen breaks while LIVE mode is
/// partial:
///
///  * Phase 2: identity (FirebaseAuth + ambulance mapping), real `offline`.
///  * Phase 3: mission stream, accept/reject/advance/setHospital, countdown,
///    history derived from the same stream (single equality filter, no
///    composite index needed — resolved/cancelled rows filtered client-side).
///  * Phase 4: GPS upload to RTDB `positions/{id}` + real `gpsLost`.
///  * **Phase 5:** hospitals directory + OSRM road geometry and
///    ETA (server `etaSeconds` preferred, km-based client fallback).
///  * **Phase 6:** chat — Firestore `missions/{id}/messages`
///    cached per mission so the seam's synchronous `messages(id)` keeps
///    working; the active mission's thread is subscribed eagerly (unread
///    badge), others on `openChat`.
///  * **Phase 7 (this file):** duty persisted as `ambulances/{id}.available`
///    (restored on login, GPS resumes) + FCM token published to
///    `ambulances/{id}.crewFcmToken` for the backend's `notifyCrew` fan-out.
///
/// Remaining (needs server-side work, not client code):
///  * `onMissionUpdate` in functions/index.js only fans out to the *patient*
///    — a one-line `notifyCrew(after.ambulanceId, missionId, to)` call is
///    needed so dispatcher/manual assignments push to the crew too
///    (the `requestAmbulance` callable already notifies).
///
/// Contract notes from the backend (Phase 0 recon):
///  * `ambulances` doc ID == plate; `crewId` = Auth uid; `base:{lat,lng}`;
///    `positions`/`missions` keys use the **doc id**.
///  * Mission statuses use the same names as [MissionStatus]; `requested`
///    (rejected/unassigned) and `cancelled` are not crew-active states.
///  * Reject = `status: 'requested'` + `ambulanceId: null` (per the LEGAL
///    map in functions) — the doc then leaves this unit's query. We insert
///    the rejected history row client-side at reject time (demo parity:
///    manual reject logs a row, countdown auto-reject doesn't).
///  * The mission doc has NO address field (the patient request flow
///    collects one but never persists it) → `pickupLabel` falls back to
///    caller name + pin coordinates.
///  * Server writes `etaSeconds` (OSRM) on routed legs — aged out
///    client-side between snapshots by a 1 Hz ticker (no position fudging;
///    GPS owns position, Phase 4).
///  * Rules already allow crew role to update `ambulances`/`missions` and
///    write RTDB `positions` — no rules changes were needed.
class FirebaseRepository extends CrewRepository {
  final CrewService _service = CrewService();
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _missionsSub;

  Timer? _countdownTimer; // incoming-job auto-reject (§5)
  Timer? _etaTicker; // 1 Hz ETA ageing between server writes

  // ── Identity (login §1) ──────────────────────────────────────────────
  @override
  bool isSignedIn = false;
  @override
  String crewName = '';
  @override
  String crewEmail = '';
  @override
  String ambulanceId = ''; // plate (display) — falls back to the doc id
  @override
  bool sessionExpired = false;

  /// Mission/RTDB key = `ambulances` doc id (== plate in the seeded fleet,
  /// but the id is the contract dispatch writes back).
  String _ambulanceDocId = '';

  bool _identityLoading = false;
  bool _identityResolved = false;

  // ── Deck data states (§3) ────────────────────────────────────────────
  @override
  bool fleetLoading = true;
  @override
  bool fleetError = false;
  @override
  bool vehicleUnmapped = false;

  // ── Cross-cutting connectivity (§14) — real in this repo ─────────────
  @override
  bool offline = false;
  @override
  bool gpsLost = false;
  @override
  bool locationPermissionDenied = false;

  // ── Duty (§3/§4): local flip + GPS upload; `available` persistence
  //    lands in Phase 7.
  @override
  bool onDuty = false;
  @override
  bool dutySwitching = false;

  final PositionService _position = PositionService();
  Timer? _positionAgeTicker; // staleness watchdog while uploading

  // ── Missions (§5/§6) — streamed (Phase 3) ────────────────────────────
  @override
  Mission? activeMission;
  @override
  int jobCountdown = 0;
  @override
  bool simulateMissionWriteError = false;
  @override
  bool simulateDutyError = false;
  @override
  bool simulateLoginError = false;

  /// Raw doc of the current active mission (profile fetches rebuild from it).
  Map<String, dynamic>? _activeDoc;
  String? _activeDocId;
  String? _activePatientId;

  /// patientId → profile, fetched once (`patients/{uid}` may not exist for
  /// guests, cached as an empty profile to avoid refetch loops).
  final Map<String, PatientProfile> _profiles = {};

  /// Eta ageing base: seconds + the instant they were recorded. Recorded
  /// from the server's OSRM `etaSeconds` (routed legs) or the client's
  /// km-based fallback when the server hasn't written one yet. Re-based
  /// whenever the doc's `updatedAt` changes (new leg) or the base changes.
  int? _serverEtaBase;
  DateTime? _serverEtaAt;
  DateTime? _serverEtaStamp; // `updatedAt` the base was derived from

  /// OSRM geometry fetch guard: one fetch per mission + leg.
  String? _routeMissionId;
  MissionStatus? _routeLeg;

  /// Ids with a queued offline advance (chip stays "pending" until the
  /// connection returns and the write syncs — §14).
  final Set<String> _pendingAdvance = {};

  /// Manual-reject rows added at reject time (docs leaving the query can't
  /// be told apart from reassignments reliably, so we don't use removals).
  final List<MissionHistoryEntry> _leftoverRows = [];

  // ── Directory (Phase 5) ──────────────────────────────────────────────
  @override
  List<Hospital> hospitals = const [];

  /// Own unit position — starts at base; GPS stream replaces it (Phase 4).
  @override
  LatLng unitPosition = const LatLng(33.5731, -7.5898); // Casablanca center
  @override
  LatLng basePosition = const LatLng(33.5731, -7.5898);
  @override
  int positionAgeSeconds = 0;

  // ── History (derived from the mission stream) ────────────────────────
  final List<MissionHistoryEntry> _historyRows = [];
  @override
  bool historyLoading = false;
  @override
  bool historyError = false;

  // ── Chat (Phase 6): Firestore threads cached for the sync seam ───────
  final Map<String, List<ChatMessage>> _chats = {};
  final Map<String, StreamSubscription<List<Map<String, dynamic>>>>
      _chatSubs = {};
  final Map<String, DateTime> _chatOpenedAt = {};

  FirebaseRepository() {
    _authSub = _service.authChanges.listen(_onAuthChanged);
    _connSub = _connectivity.onConnectivityChanged.listen(_onConnectivity);
    // Seed connectivity immediately (the stream only emits on change).
    _connectivity.checkConnectivity().then(_onConnectivity);
    // Restore an existing session (app resume / page reload).
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) _onAuthChanged(user);
  }

  @override
  List<MissionHistoryEntry> get history => _historyRows;

  // ── Identity plumbing ────────────────────────────────────────────────

  void _onAuthChanged(User? user) {
    if (user == null) {
      isSignedIn = false;
      crewEmail = '';
      crewName = '';
      ambulanceId = '';
      _ambulanceDocId = '';
      _identityResolved = false;
      fleetLoading = false;
      vehicleUnmapped = false;
      onDuty = false;
      _stopGpsSharing();
      _stopMissionsWatch();
      notifyListeners();
      return;
    }
    isSignedIn = true;
    sessionExpired = false;
    crewEmail = user.email ?? '';
    crewName = user.displayName?.isNotEmpty == true
        ? user.displayName!
        : (user.email ?? '');
    if (!_identityResolved && !_identityLoading) _resolveIdentity(user);
    notifyListeners();
  }

  /// uid → ambulance mapping (+ plate/base). The query is rules-permitted
  /// (`ambulances` read is world-readable).
  Future<void> _resolveIdentity(User user) async {
    _identityLoading = true;
    fleetLoading = true;
    vehicleUnmapped = false;
    notifyListeners();
    try {
      final id = await _service.myAmbulanceId(user.uid);
      _ambulanceDocId = id ?? '';
      ambulanceId = _ambulanceDocId;
      vehicleUnmapped = id == null;
      if (id != null) {
        final amb = await _service.ambulance(id);
        final base = amb?['base'];
        if (base is Map && base['lat'] is num && base['lng'] is num) {
          basePosition = LatLng(
            (base['lat'] as num).toDouble(),
            (base['lng'] as num).toDouble(),
          );
          unitPosition = basePosition;
        }
        final plate = amb?['plate'];
        if (plate is String && plate.isNotEmpty) ambulanceId = plate;
        // Restore duty from the persisted field so an app restart doesn't
        // silently take the unit out of dispatch (or strand it in).
        if (amb?['available'] == false) {
          onDuty = false;
        } else if (amb?['available'] == true) {
          onDuty = true;
          _resumeDutyGps();
        }
        _registerFcmToken();
      }
      _identityResolved = true;
      if (id != null) {
        _startMissionsWatch();
        _loadHospitals(); // fire-and-forget: names/locs enrich later snapshots
      }
    } catch (e) {
      debugPrint('Crew identity lookup failed: $e');
      fleetError = true;
    } finally {
      _identityLoading = false;
      fleetLoading = false;
      notifyListeners();
    }
  }

  @override
  Future<bool> signIn(String email, String password) async {
    if (simulateLoginError) return false; // demo parity: forced failure
    try {
      await _service.signIn(email.trim(), password);
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('signIn failed: ${e.code}');
      return false;
    } catch (e) {
      debugPrint('signIn failed: $e');
      return false;
    }
  }

  @override
  bool get canSignOut => activeMission == null;

  @override
  void signOut() {
    if (!canSignOut) return; // blocked mid-mission (Account §13)
    // Stop job pushes to this device; next sign-in re-publishes.
    final id = _ambulanceDocId;
    _fcmTokenSub?.cancel();
    _fcmTokenSub = null;
    if (id.isNotEmpty) {
      _service.setCrewFcmToken(id, null).catchError((Object e) {
        debugPrint('FCM token clear failed: $e');
        return null;
      });
    }
    _service.signOut();
    // _onAuthChanged clears identity + stops the mission watch.
  }

  @override
  void expireSession() {
    // Session review path (§14). Real expiry also lands as a FirebaseAuth
    // error on the next write; clearing the local session shows the login
    // screen with the "session expired" copy.
    sessionExpired = true;
    _service.signOut();
    notifyListeners();
  }

  // ── Mission stream (Phase 3) ─────────────────────────────────────────

  void _startMissionsWatch() {
    _stopMissionsWatch();
    historyLoading = true;
    _missionsSub = _service.watchMissionsFor(_ambulanceDocId).listen(
      _onMissions,
      onError: (Object e) {
        debugPrint('Mission stream error: $e');
        historyLoading = false;
        historyError = true;
        notifyListeners();
      },
    );
  }

  void _stopMissionsWatch() {
    _missionsSub?.cancel();
    _missionsSub = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _etaTicker?.cancel();
    _etaTicker = null;
    activeMission = null;
    _activeDoc = null;
    _activeDocId = null;
    _activePatientId = null;
    _historyRows.clear();
    _leftoverRows.clear();
    _pendingAdvance.clear();
    _stopChatWatch();
    jobCountdown = 0;
    historyLoading = false;
    historyError = false;
  }

  void _onMissions(QuerySnapshot<Map<String, dynamic>> snap) {
    historyLoading = false;
    historyError = false;

    Mission? active;
    final doneRows = <MissionHistoryEntry>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final rawStatus = data['status'];
      // Cancelled (patient/dispatcher) — still assigned to this unit, but
      // not an active mission; surfaces as a history row (§11 variant).
      if (rawStatus == 'cancelled') {
        doneRows.add(_historyFrom(doc.id, data, cancelled: true));
        continue;
      }
      final status = _statusOf(rawStatus);
      if (status == null) continue; // `requested` shouldn't match the query
      if (status == MissionStatus.resolved) {
        doneRows.add(_historyFrom(doc.id, data));
        continue;
      }
      final candidate = _missionFrom(doc.id, data, status);
      if (candidate == null) continue;
      if (active == null || candidate.createdAt.isAfter(active.createdAt)) {
        active = candidate;
      }
    }

    // History = rows from missions that left our view (manual rejects) +
    // terminal missions still in the query, newest first.
    _historyRows
      ..clear()
      ..addAll([..._leftoverRows, ...doneRows]
        ..sort((a, b) => b.endedAt.compareTo(a.endedAt)));

    final changed =
        active?.id != activeMission?.id || active?.status != activeMission?.status;
    if (changed) {
      // New mission or new phase: reset the countdown + ETA base.
      _countdownTimer?.cancel();
      _countdownTimer = null;
      _serverEtaBase = null;
      _serverEtaAt = null;
      _serverEtaStamp = null;
    }
    activeMission = active;
    if (active == null) {
      _activeDoc = null;
      _activeDocId = null;
      _activePatientId = null;
      jobCountdown = 0;
      _etaTicker?.cancel();
      _etaTicker = null;
      _routeMissionId = null;
      _routeLeg = null;
    } else {
      _activeDoc = _docOf(snap, active.id);
      _activeDocId = active.id;
      final rawPatient = _activeDoc?['patientId'];
      _activePatientId = rawPatient is String ? rawPatient : null;
      if (active.status == MissionStatus.assigned) {
        _startCountdown();
      } else {
        _countdownTimer?.cancel();
        _countdownTimer = null;
      }
      _startEtaTicker();
      _maybeLoadProfile(active);
      _maybeFetchLegRoute(active); // OSRM geometry for the active leg
      _watchActiveChat(); // unread badge is live before chat is opened
    }
    notifyListeners();
  }

  Map<String, dynamic>? _docOf(
          QuerySnapshot<Map<String, dynamic>> snap, String id) =>
      snap.docs.where((d) => d.id == id).firstOrNull?.data();

  // ── Doc → model parsing ──────────────────────────────────────────────

  MissionStatus? _statusOf(Object? raw) {
    if (raw is! String) return null;
    for (final s in MissionStatus.values) {
      if (s.name == raw) return s;
    }
    return null; // requested / cancelled / unknown
  }

  Mission? _missionFrom(
      String id, Map<String, dynamic> data, MissionStatus status) {
    final loc = data['location'];
    if (loc is! Map || loc['lat'] is! num || loc['lng'] is! num) return null;
    final pickup = LatLng(
      (loc['lat'] as num).toDouble(),
      (loc['lng'] as num).toDouble(),
    );

    final patientId = data['patientId'] as String?;
    final patientName = data['patientName'] as String?;
    final profile = patientId != null
        ? (_profiles[patientId] ?? PatientProfile(name: patientName))
        : PatientProfile(name: patientName);

    final timeline = <MissionStatus, DateTime>{};
    final rawTimeline = data['timeline'];
    if (rawTimeline is Map) {
      rawTimeline.forEach((key, value) {
        final s = _statusOf(key);
        final ts = _ts(value);
        if (s != null && ts != null) timeline[s] = ts;
      });
    }

    // Server OSRM ETA (routed legs) — adopt it and age it from `updatedAt`.
    // The stamp guards against re-basing on every snapshot (which would
    // freeze the countdown at `base` forever).
    final serverEta = data['etaSeconds'];
    final updatedAt = _ts(data['updatedAt']);
    if (serverEta is num && serverEta > 0) {
      if (_serverEtaBase != serverEta.toInt() ||
          _serverEtaStamp != updatedAt) {
        _serverEtaBase = serverEta.toInt();
        _serverEtaAt = updatedAt ?? DateTime.now();
        _serverEtaStamp = updatedAt;
      }
    }

    final hospitalId = data['hospitalId'] as String?;
    final hospitalLoc = _hospitalLocation(hospitalId);
    final target = (status == MissionStatus.transporting && hospitalLoc != null)
        ? hospitalLoc
        : pickup;
    final distance = status == MissionStatus.atHospital
        ? 0.0
        : _straightKm(unitPosition, target);

    return Mission(
      id: id,
      status: status,
      patient: profile,
      pickupLabel: _pickupLabel(patientName, pickup),
      pickup: pickup,
      hospitalId: hospitalId,
      hospitalName: _hospitalName(hospitalId),
      createdAt: _ts(data['createdAt']) ?? DateTime.now(),
      timeline: timeline,
      etaSeconds: _agedEta(),
      distanceKm: distance,
      offlinePending: _pendingAdvance.contains(id),
    );
  }

  /// Backend gap: missions carry no address. Show the caller when known,
  /// else the pin coordinates (the route row only takes up to the comma).
  String _pickupLabel(String? patientName, LatLng pickup) {
    if (patientName != null && patientName.isNotEmpty) {
      return '$patientName · ${pickup.latitude.toStringAsFixed(4)}, '
          '${pickup.longitude.toStringAsFixed(4)}';
    }
    return '${pickup.latitude.toStringAsFixed(4)}, '
        '${pickup.longitude.toStringAsFixed(4)}';
  }

  String? _hospitalName(String? id) {
    if (id == null) return null;
    for (final h in hospitals) {
      if (h.id == id) return h.name;
    }
    return null; // Phase 5 loads the directory
  }

  LatLng? _hospitalLocation(String? id) {
    if (id == null) return null;
    for (final h in hospitals) {
      if (h.id == id) return h.location;
    }
    return null;
  }

  double _straightKm(LatLng a, LatLng b) {
    final km = const Distance().as(LengthUnit.Kilometer, a, b);
    return double.parse(km.toStringAsFixed(2));
  }

  DateTime? _ts(Object? v) => v is Timestamp ? v.toDate() : null;

  // ── Incoming-job countdown (§5) ──────────────────────────────────────

  void _startCountdown() {
    if (_countdownTimer != null) return;
    // 30s from first observation of this assigned mission (the server has
    // no auto-reject; the client owns the timer exactly like the demo).
    jobCountdown = 30;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final m = activeMission;
      if (m == null || m.status != MissionStatus.assigned) {
        t.cancel();
        _countdownTimer = null;
        return;
      }
      jobCountdown--;
      if (jobCountdown <= 0) {
        t.cancel();
        _countdownTimer = null;
        rejectJob(auto: true);
      } else {
        notifyListeners();
      }
    });
  }

  // ── ETA ageing ticker (1 Hz — GPS owns position, Phase 4) ────────────

  int _agedEta() {
    final base = _serverEtaBase;
    if (base == null) return 0;
    final at = _serverEtaAt;
    if (at == null) return base;
    final elapsed = DateTime.now().difference(at).inSeconds;
    return (base - elapsed).clamp(0, base);
  }

  void _startEtaTicker() {
    if (_etaTicker != null) return;
    _etaTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final m = activeMission;
      if (m == null) {
        _etaTicker?.cancel();
        _etaTicker = null;
        return;
      }
      if (_serverEtaBase == null) return;
      final aged = _agedEta();
      if (aged != m.etaSeconds) {
        m.etaSeconds = aged;
        notifyListeners();
      }
    });
  }

  // ── Patient profile (async enrich of the active mission) ─────────────

  void _maybeLoadProfile(Mission m) {
    final uid = _activePatientId;
    if (uid == null || _profiles.containsKey(uid)) return;
    _service.patientProfile(uid).then((map) {
      _profiles[uid] = map == null
          ? const PatientProfile() // no doc yet — cache, don't refetch
          : _profileFrom(map, m.patient.name);
      _rebuildActiveProfile();
    }).catchError((Object e) {
      debugPrint('Patient profile load failed: $e');
    });
  }

  PatientProfile _profileFrom(Map<String, dynamic> data, String? name) {
    List<String> stringList(Object? v) {
      if (v is List) return v.whereType<String>().toList();
      if (v is String && v.trim().isNotEmpty) {
        return v
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      return const [];
    }

    final contacts = <String>[];
    String? contactPhone;
    final rawContacts = data['contacts'];
    if (rawContacts is List) {
      for (final c in rawContacts) {
        if (c is Map) {
          final cname = c['name'] as String?;
          final rel = c['relationship'] as String?;
          final phone = c['phone'] as String?;
          contactPhone ??= phone;
          contacts.add([
            if (cname != null && cname.isNotEmpty) cname,
            if (rel != null && rel.isNotEmpty) rel,
          ].join(' · '));
        }
      }
    }
    final emergency = data['emergencyContact'];
    if (emergency is String && emergency.isNotEmpty) {
      contactPhone ??= emergency;
      contacts.add(emergency);
    }

    return PatientProfile(
      name: name,
      bloodType: data['bloodType'] as String?,
      allergies: stringList(data['allergies']),
      conditions: stringList(data['conditions']),
      contacts: contacts,
      contactPhone: contactPhone,
    );
  }

  /// Swap the rebuilt profile into the live mission object.
  void _rebuildActiveProfile() {
    final doc = _activeDoc;
    final id = _activeDocId;
    if (doc == null || id == null) return;
    final status = _statusOf(doc['status']);
    if (status == null || status == MissionStatus.resolved) return;
    final fresh = _missionFrom(id, doc, status);
    if (fresh == null) return;
    activeMission = fresh;
    notifyListeners();
  }

  // ── Directory + OSRM geometry (Phase 5) ──────────────────────────────

  /// Hospital directory (`hospitals` is world-readable per rules). Loaded
  /// once after sign-in; the next mission snapshot picks the names up.
  Future<void> _loadHospitals() async {
    try {
      final raw = await _service.hospitals();
      final list = <Hospital>[];
      for (final h in raw) {
        final id = h['id'];
        if (id == null) continue;
        final loc = await _service.hospitalLocation(id);
        if (loc == null || loc['lat'] is! num || loc['lng'] is! num) continue;
        list.add(Hospital(
          id: id,
          name: h['name'] ?? id,
          location: LatLng(
            (loc['lat'] as num).toDouble(),
            (loc['lng'] as num).toDouble(),
          ),
        ));
      }
      hospitals = list;
      // Enrich the live mission + history rows with names/locations now
      // that the directory landed.
      _rebuildActiveProfile();
    } catch (e) {
      debugPrint('Hospital directory load failed: $e'); // sheets stay empty
    }
  }

  /// OSRM road geometry for the leg the unit is currently driving (pickup
  /// leg pre-accept, hospital leg while transporting). One fetch per
  /// mission+leg; any failure falls back to the straight line the mission
  /// already carries (design rule: geometry never blocks the deck).
  Future<void> _maybeFetchLegRoute(Mission m) async {
    if (offline) return;
    final leg = switch (m.status) {
      MissionStatus.assigned ||
      MissionStatus.accepted ||
      MissionStatus.enRoute =>
        MissionStatus.enRoute, // pickup leg
      MissionStatus.transporting => MissionStatus.transporting,
      _ => null,
    };
    if (leg == null) return;
    if (_routeMissionId == m.id && _routeLeg == leg) return; // already tried
    _routeMissionId = m.id;
    _routeLeg = leg;

    final from = unitPosition;
    final to = leg == MissionStatus.transporting
        ? (_hospitalLocation(m.hospitalId) ?? m.pickup)
        : m.pickup;
    final route = await RouteService.drivingRoute(from, to);
    if (route == null) return; // straight-line fallback stays
    final live = activeMission;
    if (live == null || live.id != m.id || live.status != m.status) return;
    if (leg == MissionStatus.transporting) {
      live.routeToHospital = route;
    } else {
      live.routeToPickup = route;
    }
    final km = RouteService.totalKm(route);
    live.distanceKm = double.parse(km.toStringAsFixed(1));
    // Road ETA only when the server hasn't already written its own number.
    if (_serverEtaBase == null) {
      live.etaSeconds = (km * 150).round(); // ~24 km/h Casablanca traffic
      live.legTotalSeconds = live.etaSeconds;
      _serverEtaBase = live.etaSeconds;
      _serverEtaAt = DateTime.now();
      _serverEtaStamp = null;
    }
    notifyListeners();
  }

  // ── Mission lifecycle actions ────────────────────────────────────────

  @override
  bool actionBlockedByHospital(MissionStatus s) =>
      s == MissionStatus.onScene && activeMission?.hospitalId == null;

  @override
  void acceptJob() {
    final m = activeMission;
    if (m == null || m.status != MissionStatus.assigned) return;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    jobCountdown = 0;
    // Optimistic; the stream confirms (server also stamps timeline.accepted).
    m.status = MissionStatus.accepted;
    m.timeline = {...m.timeline, MissionStatus.accepted: DateTime.now()};
    _serverEtaBase = null;
    notifyListeners();
    _service.accept(m.id).catchError((Object e) {
      debugPrint('accept failed: $e');
      _revertActive(); // discard the optimistic state
      return null;
    });
  }

  @override
  void rejectJob({bool auto = false}) {
    final m = activeMission;
    if (m == null) return;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    activeMission = null;
    _activeDoc = null;
    _activeDocId = null;
    _activePatientId = null;
    jobCountdown = 0;
    _etaTicker?.cancel();
    _etaTicker = null;
    // Manual reject logs a history row (§11); countdown auto-reject doesn't.
    if (!auto) _leftoverRows.insert(0, _rejectedRow(m.id, const {}));
    notifyListeners();
    // Backend contract: back to the pool, unassigned (LEGAL: assigned→requested).
    _service.reject(m.id).catchError((Object e) {
      debugPrint('reject failed: $e');
      return null;
    });
  }

  /// One-tap advance → next lifecycle status; server-validated via LEGAL
  /// transitions (a rejected write surfaces as `false` → snackbar §6).
  @override
  Future<bool> advanceStatus() async {
    final m = activeMission;
    if (m == null || actionBlockedByHospital(m.status)) return false;
    final next = MissionStatus.values[m.status.index + 1];
    m.offlinePending = offline;
    if (offline) _pendingAdvance.add(m.id);
    notifyListeners();
    try {
      if (offline) {
        // Firestore queues the write locally and syncs on reconnect —
        // report pending (not failed) exactly like the spec'd §14 state.
        _service.advance(m.id, next.name);
        return true;
      }
      await _service.advance(m.id, next.name);
      m.offlinePending = false;
      // Local optimistic tick so the stepper moves before the snapshot.
      m.status = next;
      m.timeline = {...m.timeline, next: DateTime.now()};
      if (next == MissionStatus.resolved) _serverEtaBase = null;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('advance failed: $e');
      m.offlinePending = false;
      notifyListeners();
      return false; // caller shows the error snackbar (spec §6)
    }
  }

  /// Re-read the server's version of the active mission (write failed and
  /// the optimistic state must be discarded).
  void _revertActive() {
    final doc = _activeDoc;
    final id = _activeDocId;
    if (doc == null || id == null) return;
    final status = _statusOf(doc['status']);
    if (status == null || status == MissionStatus.resolved) return;
    activeMission = _missionFrom(id, doc, status);
    notifyListeners();
  }

  @override
  void pickHospital(Hospital h) {
    final m = activeMission;
    if (m == null) return;
    m.hospitalId = h.id;
    m.hospitalName = h.name;
    m.distanceKm = _straightKm(m.pickup, h.location);
    notifyListeners();
    _service.setHospital(m.id, h.id).catchError((Object e) {
      debugPrint('setHospital failed: $e');
      return null;
    });
  }

  // ── History rows ─────────────────────────────────────────────────────

  MissionHistoryEntry _historyFrom(String id, Map<String, dynamic> data,
      {bool cancelled = false}) {
    final createdAt = _ts(data['createdAt']) ?? DateTime.now();
    final timeline = <MissionStatus, DateTime>{};
    final rawTimeline = data['timeline'];
    if (rawTimeline is Map) {
      rawTimeline.forEach((key, value) {
        final s = _statusOf(key);
        final ts = _ts(value);
        if (s != null && ts != null) timeline[s] = ts;
      });
    }
    final endedAt =
        timeline[MissionStatus.resolved] ?? _ts(data['updatedAt']) ?? createdAt;
    final hospitalId = data['hospitalId'] as String?;
    final hospital = _hospitalName(hospitalId) ?? hospitalId;
    final patientId = data['patientId'] as String?;
    final profile = patientId != null ? _profiles[patientId] : null;
    final isGuest = patientId == null;
    final bloodType = profile?.bloodType;
    final loc = data['location'];
    final label = loc is Map && loc['lat'] is num && loc['lng'] is num
        ? _pickupLabel(
            data['patientName'] as String?,
            LatLng((loc['lat'] as num).toDouble(),
                (loc['lng'] as num).toDouble()))
        : 'Pickup';
    final summary = isGuest
        ? 'Guest'
        : (bloodType != null ? '$bloodType patient' : 'Patient');

    return MissionHistoryEntry(
      id: id,
      route: cancelled
          ? '$label · cancelled'
          : '$label → ${hospital ?? 'Hospital'}',
      patientSummary: cancelled ? '$summary · cancelled' : summary,
      endedAt: endedAt,
      duration: endedAt.difference(createdAt),
      hospital: hospital,
      bloodType: bloodType,
      isGuest: isGuest,
      timeline: timeline.isEmpty ? null : timeline,
    );
  }

  MissionHistoryEntry _rejectedRow(String id, Map<String, dynamic> data) {
    final patientName = data['patientName'] as String?;
    return MissionHistoryEntry(
      id: id,
      route: '${patientName ?? 'Pickup'} · rejected',
      patientSummary: patientName == null ? 'Guest' : 'Declined',
      endedAt: DateTime.now(),
      duration: Duration.zero,
    );
  }

  // ── Real connectivity ────────────────────────────────────────────────

  void _onConnectivity(List<ConnectivityResult> result) {
    final nowOffline =
        result.isEmpty || result.every((r) => r == ConnectivityResult.none);
    if (nowOffline == offline) return;
    offline = nowOffline;
    if (!nowOffline) {
      // Queued advances are syncing — the stream confirms them shortly.
      _pendingAdvance.clear();
      if (activeMission != null) activeMission!.offlinePending = false;
    }
    notifyListeners();
  }

  // ── Duty (Phase 7): persisted as `ambulances/{id}.available` — the
  //    field dispatch's nearestUnit() already filters on.

  /// Going on duty shares GPS with dispatch (Phase 4) and flips
  /// `available` so `nearestUnit()` includes this unit in matching. Off
  /// duty: upload stops, `available: false` takes the unit out of rotation.
  @override
  Future<void> setOnDuty(bool value) async {
    if (activeMission != null && !value) return; // blocked mid-mission (§13)
    if (_ambulanceDocId.isEmpty) return; // unmapped — nothing to persist to
    dutySwitching = true;
    notifyListeners();
    try {
      if (value) {
        _positionUploading = await _position.startUpload(
          _ambulanceDocId,
          onFix: _onPositionFix,
          onError: _onGpsError,
        );
        locationPermissionDenied = !_positionUploading;
        gpsLost = !_positionUploading;
        _startPositionAgeTicker();
      } else {
        _stopGpsSharing();
      }
      await _service.setAvailable(_ambulanceDocId, value);
      onDuty = value;
    } catch (e) {
      debugPrint('duty toggle failed: $e');
      onDuty = false;
      _stopGpsSharing();
      // Caller shows "Couldn't change duty status." (§4) and the switch
      // snaps back because onDuty stayed false.
    } finally {
      dutySwitching = false;
      notifyListeners();
    }
  }

  @override
  Future<bool> ensureLocationPermission({bool prompt = true}) async {
    final ok = await PositionService.ensurePermission(prompt: prompt);
    locationPermissionDenied = !ok;
    if (ok && onDuty && !_positionUploading) {
      // Permission came back (e.g. after Settings) while still on duty.
      _positionUploading = await _position.startUpload(
        _ambulanceDocId,
        onFix: _onPositionFix,
        onError: _onGpsError,
      );
      _startPositionAgeTicker();
    }
    return ok;
  }

  // ── FCM job push (Phase 7) ───────────────────────────────────────────

  /// Publish this device's token where the backend's `notifyCrew()` looks
  /// it up (`ambulances/{id}.crewFcmToken`), and keep it fresh on rotation.
  /// Failures are non-fatal (no push, but the app works via the stream).
  StreamSubscription<String>? _fcmTokenSub;

  Future<void> _registerFcmToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      if (token != null && _ambulanceDocId.isNotEmpty) {
        await _service.setCrewFcmToken(_ambulanceDocId, token);
      }
      _fcmTokenSub ??= messaging.onTokenRefresh.listen((next) {
        if (_ambulanceDocId.isNotEmpty) {
          _service.setCrewFcmToken(_ambulanceDocId, next).catchError(
            (Object e) {
              debugPrint('FCM token refresh publish failed: $e');
              return null;
            },
          );
        }
      });
    } catch (e) {
      // Web without VAPID config, or messaging unsupported — job pushes
      // just don't arrive; the Firestore stream still drives the UI.
      debugPrint('FCM token registration failed: $e');
    }
  }

  /// Restart sharing after a resume/restore that found `available: true`.
  Future<void> _resumeDutyGps() async {
    _positionUploading = await _position.startUpload(
      _ambulanceDocId,
      onFix: _onPositionFix,
      onError: _onGpsError,
    );
    locationPermissionDenied = !_positionUploading;
    gpsLost = !_positionUploading;
    _startPositionAgeTicker();
    notifyListeners();
  }

  bool _positionUploading = false;

  void _onPositionFix(LatLng point) {
    unitPosition = point;
    positionAgeSeconds = 0;
    _positionUploading = true;
    if (gpsLost) gpsLost = false;
    // Live unit marker feeds honest distances for the active leg.
    final m = activeMission;
    if (m != null) {
      final target = (m.status == MissionStatus.transporting ||
              m.status == MissionStatus.atHospital)
          ? (_hospitalLocation(m.hospitalId) ?? m.pickup)
          : m.pickup;
      m.distanceKm = _straightKm(point, target);
    }
    notifyListeners();
  }

  void _onGpsError() {
    gpsLost = true;
    _positionUploading = false;
    notifyListeners();
  }

  /// Staleness watchdog: no fix for >30 s while on duty → gpsLost (the
  /// design's §14 "GPS lost" strip); recovers on the next fix.
  void _startPositionAgeTicker() {
    _positionAgeTicker?.cancel();
    _positionAgeTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!onDuty) {
        _positionAgeTicker?.cancel();
        _positionAgeTicker = null;
        return;
      }
      positionAgeSeconds++;
      if (positionAgeSeconds > 30 && !gpsLost) {
        gpsLost = true;
      }
      notifyListeners();
    });
  }

  void _stopGpsSharing() {
    _position.stopUpload();
    _positionUploading = false;
    _positionAgeTicker?.cancel();
    _positionAgeTicker = null;
    gpsLost = false;
    positionAgeSeconds = 0;
  }

  // ── Chat (Phase 6) ───────────────────────────────────────────────────

  @override
  Mission? mission(String id) =>
      activeMission?.id == id ? activeMission : null;

  @override
  List<ChatMessage> messages(String missionId) => _chats[missionId] ?? const [];

  /// Unread badge: non-crew messages newer than the last time chat was open
  /// (same rule as the demo).
  @override
  int unreadCount(String missionId) {
    final openedAt = _chatOpenedAt[missionId];
    return (_chats[missionId] ?? const [])
        .where((m) =>
            m.senderRole != 'crew' &&
            (openedAt == null || m.at.isAfter(openedAt)))
        .length;
  }

  @override
  void openChat(String missionId) {
    _chatOpenedAt[missionId] = DateTime.now();
    _watchChat(missionId);
    notifyListeners();
  }

  /// Subscribe to a mission's `messages` subcollection (rules: readable by
  /// whoever can read the parent mission — crew qualifies). The stream is
  /// newest-first from CrewService; the UI expects oldest-first, so flip it.
  void _watchChat(String missionId) {
    if (_chatSubs.containsKey(missionId)) return;
    _chatSubs[missionId] =
        _service.watchMessages(missionId).listen((rows) {
      final list = rows.reversed
          .map((r) => ChatMessage(
                text: (r['text'] as String?) ?? '',
                senderRole: (r['senderRole'] as String?) ?? '',
                at: r['at'] as DateTime? ?? DateTime.now(),
              ))
          .toList();
      _chats[missionId] = list;
      notifyListeners();
    }, onError: (Object e) {
      debugPrint('Chat stream error ($missionId): $e');
      _chatSubs.remove(missionId)?.cancel();
    });
  }

  @override
  void sendMessage(String missionId, String text, {bool quick = false}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    // Optimistic bubble (pending while offline — Firestore queues the write
    // and the stream snapshot replaces it with the server copy on sync).
    final list = _chats.putIfAbsent(missionId, () => []);
    list.add(ChatMessage(
      text: trimmed,
      senderRole: 'crew',
      at: DateTime.now(),
      pending: offline,
    ));
    _watchChat(missionId);
    notifyListeners();
    _service.sendMessage(missionId, trimmed).catchError((Object e) {
      debugPrint('sendMessage failed: $e');
      return null;
    });
  }

  /// Eagerly subscribe to the active mission's thread so the unread badge
  /// is live before the crew ever opens the chat.
  void _watchActiveChat() {
    final id = _activeDocId;
    if (id != null) _watchChat(id);
  }

  void _stopChatWatch() {
    for (final sub in _chatSubs.values) {
      sub.cancel();
    }
    _chatSubs.clear();
    _chats.clear();
    _chatOpenedAt.clear();
  }

  // ── Demo-state setters — inert here (real signals drive these) ───────

  @override
  void setOffline(bool value) {}

  @override
  void setGpsLost(bool value) {}

  @override
  void setMissionWriteError(bool value) => simulateMissionWriteError = value;

  @override
  void setLoginError(bool value) => simulateLoginError = value;

  @override
  void setDutyError(bool value) => simulateDutyError = value;

  @override
  void setFleetLoading(bool value) {}

  @override
  void setFleetError(bool value) => fleetError = value;

  @override
  void setVehicleUnmapped(bool value) {}

  @override
  void setHistoryLoading(bool value) {}

  @override
  void setHistoryError(bool value) => historyError = value;

  @override
  void dispose() {
    _fcmTokenSub?.cancel();
    _position.stopUpload();
    _positionAgeTicker?.cancel();
    _missionsSub?.cancel();
    _countdownTimer?.cancel();
    _etaTicker?.cancel();
    _authSub?.cancel();
    _connSub?.cancel();
    _stopChatWatch();
    super.dispose();
  }
}
