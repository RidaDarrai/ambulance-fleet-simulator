import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../services/crew_service.dart';
import 'crew_repository.dart';
import 'mission_status.dart';
import 'models.dart';

/// Real backend behind the [CrewRepository] seam — Firestore / Auth / RTDB,
/// the crew counterpart to patient_app's `FirebaseRepository`.
///
/// Built in phases (see the wiring plan); members not yet backed by the
/// backend return safe inert defaults so no screen breaks while LIVE mode is
/// partial:
///
///  * **Phase 2 (this file):** identity (FirebaseAuth + ambulance mapping),
///    real `offline` via connectivity_plus. Demo `set*` toggles are inert.
///  * Phase 3: mission stream + lifecycle actions.
///  * Phase 4: GPS upload to RTDB `positions/{id}` + `gpsLost`.
///  * Phase 5: hospitals directory, OSRM ETA, history query.
///  * Phase 6: chat message cache (Firestore `missions/{id}/messages`).
///  * Phase 7: duty (`ambulances/{id}.available`) + FCM token registration.
///
/// Contract notes from the backend (Phase 0 recon):
///  * `ambulances` doc ID == plate; `crewId` = Auth uid; `base:{lat,lng}`.
///  * Rules already allow crew role to update `ambulances` and write RTDB
///    `positions` — no rules changes were needed.
class FirebaseRepository extends CrewRepository {
  final CrewService _service = CrewService();
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  // ── Identity (login §1) ──────────────────────────────────────────────
  @override
  bool isSignedIn = false;
  @override
  String crewName = '';
  @override
  String crewEmail = '';
  @override
  String ambulanceId = ''; // empty = not mapped yet (or unmapped)
  @override
  bool sessionExpired = false;

  /// Resolving `users/{uid}` → `ambulances.where(crewId == uid)`.
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
  bool gpsLost = false; // driven by the GPS stream (Phase 4)

  // ── Duty (§3/§4) — persisted in Phase 7 ──────────────────────────────
  @override
  bool onDuty = false;
  @override
  bool dutySwitching = false;

  // ── Missions (§5/§6) — streamed in Phase 3 ───────────────────────────
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

  // ── History (Phase 5) ────────────────────────────────────────────────
  @override
  List<MissionHistoryEntry> history = const [];
  @override
  bool historyLoading = false;
  @override
  bool historyError = false;

  FirebaseRepository() {
    _authSub = _service.authChanges.listen(_onAuthChanged);
    _connSub = _connectivity.onConnectivityChanged.listen(_onConnectivity);
    // Seed connectivity immediately (the stream only emits on change).
    _connectivity.checkConnectivity().then(_onConnectivity);
    // Restore an existing session (app resume / page reload).
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) _onAuthChanged(user);
  }

  // ── Identity plumbing ────────────────────────────────────────────────

  void _onAuthChanged(User? user) {
    if (user == null) {
      isSignedIn = false;
      crewEmail = '';
      crewName = '';
      ambulanceId = '';
      _identityResolved = false;
      fleetLoading = false;
      vehicleUnmapped = false;
      notifyListeners();
      return;
    }
    isSignedIn = true;
    sessionExpired = false;
    crewEmail = user.displayName?.isNotEmpty == true
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
      ambulanceId = id ?? '';
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
      }
      _identityResolved = true;
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
    _service.signOut();
    // _onAuthChanged clears the identity state.
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

  // ── Duty — full persistence lands in Phase 7 ─────────────────────────

  @override
  Future<void> setOnDuty(bool value) async {
    // Not yet persisted: keep the toggle visually honest (spinner) without
    // claiming a durable state the backend doesn't record yet.
    dutySwitching = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    dutySwitching = false;
    notifyListeners();
  }

  // ── Real connectivity ────────────────────────────────────────────────

  void _onConnectivity(List<ConnectivityResult> result) {
    final nowOffline =
        result.isEmpty || result.every((r) => r == ConnectivityResult.none);
    if (nowOffline != offline) {
      offline = nowOffline;
      notifyListeners();
    }
  }

  // ── Mission lifecycle — backend-backed from Phase 3 ──────────────────

  @override
  bool actionBlockedByHospital(MissionStatus s) =>
      s == MissionStatus.onScene && activeMission?.hospitalId == null;

  @override
  void acceptJob() {}

  @override
  void rejectJob({bool auto = false}) {}

  @override
  Future<bool> advanceStatus() async => false;

  @override
  void pickHospital(Hospital h) {
    activeMission?.hospitalId = h.id;
    activeMission?.hospitalName = h.name;
    notifyListeners();
  }

  @override
  Mission? mission(String id) =>
      activeMission?.id == id ? activeMission : null;

  // ── Chat — Firestore-backed in Phase 6 ───────────────────────────────

  @override
  List<ChatMessage> messages(String missionId) => const [];

  @override
  int unreadCount(String missionId) => 0;

  @override
  void openChat(String missionId) {}

  @override
  void sendMessage(String missionId, String text, {bool quick = false}) {}

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
    _authSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}
