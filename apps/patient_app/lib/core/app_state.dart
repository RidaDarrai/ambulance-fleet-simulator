import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'mission_status.dart';

/// Simulated user location (Casablanca) and target hospital.
const LatLng kUserLocation = LatLng(33.573110, -7.589843);
const LatLng kHospital = LatLng(33.582300, -7.632500);
const String kHospitalName = "St. Mary's Hospital";

class EmergencyContact {
  String id;
  String name;
  String relationship;
  String phone;

  EmergencyContact({
    required this.id,
    required this.name,
    required this.relationship,
    required this.phone,
  });
}

/// Mutable medical profile (screen spec §11) — edits mark `pendingSync`
/// while offline and always refresh `lastUpdated`.
class MedicalProfile {
  String? bloodType;
  final List<String> allergies;
  final List<String> conditions;
  final List<EmergencyContact> contacts;
  DateTime lastUpdated;
  bool pendingSync;

  MedicalProfile({
    this.bloodType,
    List<String>? allergies,
    List<String>? conditions,
    List<EmergencyContact>? contacts,
    DateTime? lastUpdated,
    this.pendingSync = false,
  })  : allergies = allergies ?? [],
        conditions = conditions ?? [],
        contacts = contacts ?? [],
        lastUpdated = lastUpdated ?? DateTime.now();

  /// Demo seed — cleared via "Reset profile (demo)" to see the first-use
  /// empty state (spec §11).
  factory MedicalProfile.seeded() => MedicalProfile(
        bloodType: 'O+',
        allergies: ['Penicillin'],
        conditions: ['Asthma'],
        contacts: [
          EmergencyContact(
              id: 'c1',
              name: 'Sarah Alaoui',
              relationship: 'Sister',
              phone: '06 12 34 56 78'),
          EmergencyContact(
              id: 'c2',
              name: 'Dr. Benali',
              relationship: 'Doctor',
              phone: '05 22 98 76 54'),
        ],
        lastUpdated: DateTime.now().subtract(const Duration(days: 3)),
      );

  bool get isEmpty =>
      bloodType == null &&
      allergies.isEmpty &&
      conditions.isEmpty &&
      contacts.isEmpty;

  bool get incomplete => bloodType == null; // nudge target (spec §11)
}

class AmbulanceUnit {
  final String id;
  final String callsign;
  final int crewSize;
  final String vehicleType; // public crew info (spec §4)
  LatLng position;
  bool available;

  AmbulanceUnit({
    required this.id,
    required this.callsign,
    required this.crewSize,
    this.vehicleType = 'ALS',
    required this.position,
    this.available = true,
  });
}

class Incident {
  final String id;
  final LatLng pickup;
  final LatLng hospital;
  final DateTime createdAt;
  final int queuePosition; // FIFO position at submission (baseline: plain queue)
  MissionStatus status;
  int etaSeconds;
  String? unitId;
  bool addedToHistory;

  /// When each status was first reached — drives the §8 summary timestamps.
  final Map<MissionStatus, DateTime> statusTimes = {};

  /// Audit-trail snapshots (§10): captured at request/assignment time so the
  /// history stays accurate even if the fleet changes later.
  final bool medicalAttached;
  String? unitCallsign;

  Incident({
    required this.id,
    required this.pickup,
    required this.hospital,
    required this.createdAt,
    required this.status,
    this.queuePosition = 1,
    this.etaSeconds = 0,
    this.unitId,
    this.addedToHistory = false,
    this.medicalAttached = false,
    this.unitCallsign,
  }) {
    statusTimes[status] = createdAt;
  }
}

/// Client-side demo state: holds fleet + incident simulation so the UI can be
/// built and evaluated before Firebase is wired. Every model transition here
/// mirrors the baseline lifecycle; swap for RTDB/Firestore listeners later.
class AppState extends ChangeNotifier {
  // ── User / app prefs (demo toggles backed by Settings) ──────────────
  bool onboardingDone = false;
  bool isAuthenticated = false;
  bool reduceMotion = false;
  bool offline = false;
  bool notifyContacts = true;
  bool notificationsEnabled = true;
  ThemeMode themeMode = ThemeMode.light;

  /// Demo identity used by "Using your saved details" (spec §5).
  static const String userDemoName = 'Yassine Alaoui';
  static const String userDemoPhone = '06 61 23 45 67';

  // ── Pre-permission primers (screen spec §2) ─────────────────────────
  /// Shown once, before the OS location dialog (or "Not now").
  bool locationPrimerShown = false;
  bool locationGranted = false;
  bool notificationsPrimerShown = false;
  bool notificationsGranted = true; // §15 assumes granted unless denied

  // ── Notifications settings (screen spec §15) ────────────────────────
  /// Mission updates are locked ON while a mission is active (spec §15).
  bool missionAlerts = true;
  bool crewMessages = true;
  bool arrivalAlerts = true;
  bool tipsNews = false; // opt-in only, default off
  bool quietHoursRespectOs = true;
  bool notificationsDenied = false; // OS-denied → banner (§15)
  bool notificationsPendingSync = false; // offline → queued (§15)
  bool simulateNotifSaveError = false; // toggle reverts + snackbar (§15)

  // ── Privacy & appearance (screen spec §16) ──────────────────────────
  bool analyticsOptIn = false; // off by default (§16)
  bool downloadQueuedOffline = false;

  // ── Medical profile (screen spec §11–12) ────────────────────────────
  final MedicalProfile medicalProfile = MedicalProfile.seeded();
  bool medicalLoading = false;
  bool simulateSaveError = false;

  // ── Fleet & mission ─────────────────────────────────────────────────
  final List<AmbulanceUnit> units;
  final List<Incident> history = [];
  Incident? activeIncident;

  /// User pin — movable via long-press on the map (logged in, spec §3).
  LatLng userLocation = kUserLocation;

  /// Fleet loading / error / freshness (screen spec §3 states).
  bool fleetLoading = true;
  bool fleetError = false;
  DateTime lastFleetUpdate = DateTime.now();

  /// Submit-failure simulation (demo toggle, screen spec §5 error state).
  bool simulateSubmitError = false;
  bool sendFailed = false;
  LatLng? lastRequestPickup;
  bool lastRequestMedical = false;

  Timer? _ticker;

  AppState() : units = _seedUnits() {
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

  // ── Actions ─────────────────────────────────────────────────────────
  void completeOnboarding() {
    onboardingDone = true;
    notifyListeners();
  }

  void signIn() {
    isAuthenticated = true;
    notifyListeners();
  }

  void signOut() {
    isAuthenticated = false;
    notifyListeners();
  }

  /// Location primer dismissed — `granted` records the demo choice; the flag
  /// prevents re-explaining on every session ("Not now" = ask later, not never).
  void completeLocationPrimer({required bool granted}) {
    locationPrimerShown = true;
    locationGranted = granted;
    notifyListeners();
  }

  /// Notifications primer fires after the first SOS tap (spec §2 / §7).
  void completeNotificationsPrimer({required bool granted}) {
    notificationsPrimerShown = true;
    notificationsGranted = granted;
    notifyListeners();
  }

  void setOffline(bool value) {
    offline = value;
    notifyListeners();
  }

  void setReduceMotion(bool value) {
    reduceMotion = value;
    notifyListeners();
  }

  void setDarkMode(bool value) {
    themeMode = value ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  /// Appearance → System / Light / Dark (screen spec §16).
  void setThemeMode(ThemeMode value) {
    themeMode = value;
    notifyListeners();
  }

  void setNotifyContacts(bool value) {
    notifyContacts = value;
    notifyListeners();
  }

  void setNotificationsEnabled(bool value) {
    notificationsEnabled = value;
    notifyListeners();
  }

  // ── Notifications settings setters (screen spec §15) ────────────────

  /// Mission updates: locked ON while a mission is active — the UI passes
  /// `canChange: false` and this guard refuses anyway.
  bool setMissionAlerts(bool value, {bool missionActive = false}) {
    if (missionActive) return false;
    missionAlerts = value;
    _commitNotifChange();
    return true;
  }

  bool setCrewMessages(bool value) {
    crewMessages = value;
    _commitNotifChange();
    return true;
  }

  bool setArrivalAlerts(bool value) {
    arrivalAlerts = value;
    _commitNotifChange();
    return true;
  }

  bool setTipsNews(bool value) {
    tipsNews = value;
    _commitNotifChange();
    return true;
  }

  void setQuietHours(bool value) {
    quietHoursRespectOs = value;
    notifyListeners();
  }

  void setNotificationsDenied(bool value) {
    notificationsDenied = value;
    notifyListeners();
  }

  /// Offline → queued locally ("Pending sync"), flushed on reconnect.
  /// Demo save-error → the caller reverts the switch + snackbar (§15).
  void _commitNotifChange() {
    if (simulateNotifSaveError) {
      notifyListeners();
      return;
    }
    notificationsPendingSync = offline;
    notifyListeners();
  }

  // ── Privacy setters (screen spec §16) ───────────────────────────────

  void setAnalyticsOptIn(bool value) {
    analyticsOptIn = value;
    notifyListeners();
  }

  /// Long-press on the map sets the pickup pin (logged-in users, spec §3).
  void setUserLocation(LatLng point) {
    userLocation = point;
    notifyListeners();
  }

  /// Pull-to-refresh / Retry: brief skeleton, then "Updated just now".
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

  /// Demo toggles (Settings): drive the fleet error / permission-denied states.
  void setFleetError(bool value) {
    fleetError = value;
    notifyListeners();
  }

  void setLocationGranted(bool value) {
    locationGranted = value;
    notifyListeners();
  }

  void setSimulateSubmitError(bool value) {
    simulateSubmitError = value;
    notifyListeners();
  }

  void setSimulateSaveError(bool value) {
    simulateSaveError = value;
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

  bool setBloodType(String? value) {
    medicalProfile.bloodType = value;
    return _finishMedicalEdit();
  }

  bool setAllergies(List<String> value) {
    medicalProfile.allergies
      ..clear()
      ..addAll(value);
    return _finishMedicalEdit();
  }

  bool setConditions(List<String> value) {
    medicalProfile.conditions
      ..clear()
      ..addAll(value);
    return _finishMedicalEdit();
  }

  bool addContact(EmergencyContact contact) {
    medicalProfile.contacts.add(contact);
    return _finishMedicalEdit();
  }

  bool updateContact(EmergencyContact contact) {
    return _finishMedicalEdit();
  }

  bool removeContact(EmergencyContact contact) {
    medicalProfile.contacts.remove(contact);
    return _finishMedicalEdit();
  }

  /// Demo helper — wipe the profile to see the first-use empty state (§11).
  void resetMedicalProfile() {
    medicalProfile
      ..bloodType = null
      ..allergies.clear()
      ..conditions.clear()
      ..contacts.clear();
    notifyListeners();
  }

  /// One-tap panic: fire immediately, cancellable for 5s (locked decision #1).
  /// `pickup` = the confirmed pin from the request flow (spec §5).
  /// When `simulateSubmitError` is on, nothing is created and `sendFailed`
  /// drives the error state on the queued screen (spec §6 error).
  void triggerRequest({LatLng? pickup, bool? medicalAttached}) {
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

  void cancelRequest() {
    activeIncident = null;
    sendFailed = false;
    notifyListeners();
  }

  int _queuePosition() => 2; // demo FIFO position (baseline: plain queue)

  /// Called from "Back to map" / "Done" after the mission resolves.
  void clearActiveIncident() {
    activeIncident = null;
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