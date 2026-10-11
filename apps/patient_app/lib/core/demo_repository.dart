import 'dart:async';

import 'package:latlong2/latlong.dart';

import 'app_repository.dart';
import 'mission_status.dart';
import 'models.dart';

/// In-memory simulation the patient UI was designed against. Every model
/// transition here mirrors the baseline lifecycle (baseline-report.md §4).
///
/// This is the "demo" data source behind the runtime switch — it keeps
/// working so UI walkthroughs and the Settings "State (demo)" toggles still
/// function for design review, exactly as before the repository seam existed.
class DemoRepository extends AppRepository {
  // ── Data state ──────────────────────────────────────────────────────
  @override
  final List<AmbulanceUnit> units;
  @override
  final List<Incident> history = [];
  @override
  Incident? activeIncident;
  @override
  final MedicalProfile medicalProfile = MedicalProfile.seeded();

  /// User pin — movable via long-press on the map (logged in, spec §3).
  @override
  LatLng userLocation = kUserLocation;

  /// Demo draws a straight unit→target line (no real routing).
  @override
  List<LatLng>? activeRoute;

  @override
  bool isAuthenticated = false;
  @override
  bool offline = false;

  // ── Fleet loading / error / freshness (screen spec §3 states) ───────
  @override
  bool fleetLoading = true;
  @override
  bool fleetError = false;
  @override
  DateTime lastFleetUpdate = DateTime.now();
  @override
  bool medicalLoading = false;

  // ── Submit-failure simulation (demo toggle, screen spec §5 error) ───
  @override
  bool simulateSubmitError = false;
  @override
  bool simulateSaveError = false;
  @override
  bool sendFailed = false;
  @override
  LatLng? lastRequestPickup;
  @override
  bool lastRequestMedical = false;

  Timer? _ticker;

  DemoRepository() : units = _seedUnits() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    // Initial fleet fetch skeleton (loading state, ~1.4s).
    Timer(const Duration(milliseconds: 1400), () {
      fleetLoading = false;
      lastFleetUpdate = DateTime.now();
      notifyListeners();
    });
  }

  static List<AmbulanceUnit> _seedUnits() => [
        AmbulanceUnit(
            id: 'u1',
            callsign: 'A-11',
            crewSize: 3,
            vehicleType: 'ALS',
            position: LatLng(33.5600, -7.6050)),
        AmbulanceUnit(
            id: 'u2',
            callsign: 'A-12',
            crewSize: 2,
            vehicleType: 'BLS',
            position: LatLng(33.5850, -7.5700)),
        AmbulanceUnit(
            id: 'u3',
            callsign: 'B-04',
            crewSize: 3,
            vehicleType: 'ALS',
            position: LatLng(33.5500, -7.6400)),
      ];

  // ── Incident simulation schedule (seconds since request) ────────────
  static const double tDispatch = 1.5;
  static const double tEnRoute = 3.5;
  static const double tOnScene = tEnRoute + 90;
  static const double tTransport = tOnScene + 10;
  static const double tAtHospital = tTransport + 120;
  static const double tResolved = tAtHospital + 8;

  // ── Auth actions ────────────────────────────────────────────────────
  @override
  void signIn() {
    isAuthenticated = true;
    notifyListeners();
  }

  @override
  void signOut() {
    isAuthenticated = false;
    notifyListeners();
  }

  // ── Location & connectivity ─────────────────────────────────────────
  @override
  void setUserLocation(LatLng point) {
    userLocation = point;
    notifyListeners();
  }

  @override
  void setOffline(bool value) {
    offline = value;
    notifyListeners();
  }

  // ── Fleet ───────────────────────────────────────────────────────────
  /// Pull-to-refresh / Retry: brief skeleton, then "Updated just now".
  @override
  void refreshFleet() {
    fleetLoading = true;
    fleetError = false;
    notifyListeners();
    Timer(const Duration(milliseconds: 900), () {
      fleetLoading = false;
      lastFleetUpdate = DateTime.now();
      notifyListeners();
    });
  }

  @override
  void setFleetError(bool value) {
    fleetError = value;
    notifyListeners();
  }

  // ── Demo error-simulation setters ───────────────────────────────────
  @override
  void setSimulateSubmitError(bool value) {
    simulateSubmitError = value;
    notifyListeners();
  }

  @override
  void setSimulateSaveError(bool value) {
    simulateSaveError = value;
    notifyListeners();
  }

  // ── Incident lifecycle ──────────────────────────────────────────────
  /// One-tap panic: fire immediately, cancellable for 5s (locked decision #1).
  /// `pickup` = the confirmed pin from the request flow (spec §5).
  /// When `simulateSubmitError` is on, nothing is created and `sendFailed`
  /// drives the error state on the queued screen (spec §6 error).
  @override
  void triggerRequest(
      {LatLng? pickup,
      bool? medicalAttached,
      String? guestName,
      String? guestPhone}) {
    if (activeIncident != null) return;
    lastRequestPickup = pickup ?? userLocation;
    if (medicalAttached != null) lastRequestMedical = medicalAttached;
    if (simulateSubmitError) {
      sendFailed = true;
      notifyListeners();
      return;
    }
    sendFailed = false;
    activeIncident = Incident(
      id: 'INC-${DateTime.now().millisecondsSinceEpoch % 100000}',
      pickup: lastRequestPickup!,
      medicalAttached: lastRequestMedical,
      hospital: kHospital,
      createdAt: DateTime.now(),
      status: MissionStatus.pending,
      queuePosition: _queuePosition(),
      etaSeconds: 0,
    );
    notifyListeners();
  }

  @override
  void cancelRequest() {
    activeIncident = null;
    sendFailed = false;
    notifyListeners();
  }

  int _queuePosition() => 2; // demo FIFO position (baseline: plain queue)

  /// Called from "Back to map" / "Done" after the mission resolves.
  @override
  void clearActiveIncident() {
    activeIncident = null;
    notifyListeners();
  }

  // ── Medical profile mutations (screen spec §11–12) ──────────────────

  /// Save driver for editors: returns `false` when the demo save-error
  /// toggle is on (form data is kept, spec §11 error).
  bool _finishMedicalEdit() {
    if (simulateSaveError) return false;
    medicalProfile.lastUpdated = DateTime.now();
    medicalProfile.pendingSync = offline; // queued while offline (§11)
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
  bool updateContact(EmergencyContact contact) {
    return _finishMedicalEdit();
  }

  @override
  bool removeContact(EmergencyContact contact) {
    medicalProfile.contacts.remove(contact);
    return _finishMedicalEdit();
  }

  /// Demo helper — wipe the profile to see the first-use empty state (§11).
  @override
  void resetMedicalProfile() {
    medicalProfile
      ..bloodType = null
      ..allergies.clear()
      ..conditions.clear()
      ..contacts.clear();
    notifyListeners();
  }

  // ── Simulation tick (1s) ────────────────────────────────────────────
  void _tick() {
    final inc = activeIncident;
    if (inc == null) return; // map is idle, units stay parked

    if (offline) {
      // Offline: hold the request pending — UI shows "Waiting for connection".
      if (inc.status != MissionStatus.pending) {
        inc.status = MissionStatus.pending;
        notifyListeners();
      }
      return;
    }

    final el =
        DateTime.now().difference(inc.createdAt).inMilliseconds / 1000.0;

    MissionStatus next;
    int eta = 0;
    if (el < tDispatch) {
      next = MissionStatus.pending;
    } else if (el < tEnRoute) {
      next = MissionStatus.dispatched;
    } else if (el < tOnScene) {
      next = MissionStatus.enRoute;
      eta = (tOnScene - el).ceil();
    } else if (el < tTransport) {
      next = MissionStatus.onScene;
    } else if (el < tAtHospital) {
      next = MissionStatus.transporting;
      eta = (tAtHospital - el).ceil();
    } else if (el < tResolved) {
      next = MissionStatus.atHospital;
    } else {
      next = MissionStatus.resolved;
    }

    // Assign nearest unit on dispatch (baseline: automatic suggestion).
    if (next == MissionStatus.dispatched && inc.unitId == null) {
      final unit = _nearestUnit(inc.pickup);
      inc.unitId = unit.id;
      inc.unitCallsign = unit.callsign; // §10 audit-trail snapshot
      unit.available = false;
    }

    // Move the assigned unit toward its current target.
    final unit = inc.unitId == null ? null : _unitById(inc.unitId!);
    if (unit != null) {
      final target = switch (next) {
        MissionStatus.transporting || MissionStatus.atHospital =>
          inc.hospital,
        _ => inc.pickup,
      };
      unit.position = _lerp(unit.position, target, 0.04);
      lastFleetUpdate = DateTime.now(); // "Updated Xs ago" freshness label
    }

    final bool statusChanged = next != inc.status;
    final bool etaChanged = eta != inc.etaSeconds;

    if (statusChanged) inc.statusTimes[next] = DateTime.now();

    if (next == MissionStatus.resolved && !inc.addedToHistory) {
      inc.addedToHistory = true;
      history.insert(0, inc);
      if (unit != null) unit.available = true;
    }

    inc.status = next;
    inc.etaSeconds = eta;

    if (statusChanged || etaChanged) notifyListeners();
  }

  static const Distance _dist = Distance();

  AmbulanceUnit _nearestUnit(LatLng point) {
    return units
        .where((u) => u.available)
        .reduce((a, b) =>
            _dist.as(LengthUnit.Meter, a.position, point) <
                    _dist.as(LengthUnit.Meter, b.position, point)
                ? a
                : b);
  }

  AmbulanceUnit? _unitById(String id) {
    for (final u in units) {
      if (u.id == id) return u;
    }
    return null;
  }

  /// Moves [from] 100*[t]% of the way toward [to] (simple easing).
  LatLng _lerp(LatLng from, LatLng to, double t) =>
      LatLng(from.latitude + (to.latitude - from.latitude) * t,
          from.longitude + (to.longitude - from.longitude) * t);

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
