import 'dart:async';

import 'package:latlong2/latlong.dart';

import 'crew_repository.dart';
import 'mission_status.dart';
import 'models.dart';
import 'route_service.dart';

/// In-memory simulation the crew UI was designed against. Every transition
/// here mirrors the baseline mission lifecycle. It seeds a full Casablanca
/// shift, delivers an incoming job shortly after going on duty, and drives
/// the unit along real OSRM road geometry.
///
/// This is the "demo" data source behind the runtime seam — it keeps working
/// so UI walkthroughs and the Account "State (demo)" toggles still function
/// for design review, exactly as before the repository seam existed.
class DemoRepository extends CrewRepository {
  // ── Identity (login §1) ──────────────────────────────────────────────
  @override
  bool isSignedIn = false;
  @override
  String crewName = 'Crew One';
  @override
  String crewEmail = 'crew@sim.local';
  @override
  String ambulanceId = 'AMB-07';
  @override
  bool sessionExpired = false;
  @override
  bool simulateLoginError = false;

  // ── Duty (§3/§4) ─────────────────────────────────────────────────────
  @override
  bool onDuty = false;
  @override
  bool dutySwitching = false;
  @override
  bool simulateDutyError = false; // toggle reverts + error copy (§4)

  // ── Deck data states (§3) ────────────────────────────────────────────
  @override
  bool fleetLoading = false;
  @override
  bool fleetError = false; // map error card + Retry
  @override
  bool vehicleUnmapped = false; // account not linked to a vehicle

  // ── Cross-cutting (§14) ──────────────────────────────────────────────
  @override
  bool offline = false;
  @override
  bool gpsLost = false;

  // ── History states (§11) ─────────────────────────────────────────────
  @override
  bool historyLoading = false;
  @override
  bool historyError = false;

  // ── Missions (§5/§6) ─────────────────────────────────────────────────
  @override
  Mission? activeMission;
  @override
  int jobCountdown = 30;
  @override
  bool simulateMissionWriteError = false;
  final List<MissionHistoryEntry> _history = [];
  final Map<String, List<ChatMessage>> _chats = {};

  Timer? _countdownTimer;
  Timer? _missionTicker;

  // ── Directory data ───────────────────────────────────────────────────
  @override
  final List<Hospital> hospitals = const [
    Hospital(
        id: 'h-central',
        name: 'Central Hospital',
        location: LatLng(33.5731, -7.5898)),
    Hospital(
        id: 'h-ibnsina',
        name: 'Ibn Sina Hospital',
        location: LatLng(33.595, -7.618)),
  ];

  /// Own unit position (RTDB `positions/{ambulanceId}` in the real app).
  @override
  LatLng unitPosition = const LatLng(33.5629, -7.5705); // Maârif-ish base
  @override
  final LatLng basePosition = const LatLng(33.5629, -7.5705);
  @override
  int positionAgeSeconds = 4;

  DemoRepository() {
    _seed();
  }

  @override
  List<MissionHistoryEntry> get history => _history;

  @override
  bool get canSignOut => activeMission == null;

  // ── Login (§1) ───────────────────────────────────────────────────────

  /// Demo accepts the seeded crew credentials; anything else fails.
  @override
  Future<bool> signIn(String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (simulateLoginError ||
        email.trim() != crewEmail ||
        password != 'crew12345') {
      return false;
    }
    isSignedIn = true;
    sessionExpired = false;
    notifyListeners();
    return true;
  }

  @override
  void signOut() {
    if (activeMission != null) return; // blocked mid-mission (Account §13)
    isSignedIn = false;
    onDuty = false;
    notifyListeners();
  }

  @override
  void expireSession() {
    sessionExpired = true;
    isSignedIn = false;
    onDuty = false;
    notifyListeners();
  }

  // ── Duty (§3/§4) ─────────────────────────────────────────────────────

  /// Toggling while a mission is active is blocked (Account §13 copy).
  @override
  Future<void> setOnDuty(bool value) async {
    if (activeMission != null && !value) return;
    dutySwitching = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (simulateDutyError) {
      dutySwitching = false;
      notifyListeners();
      return; // caller shows "Couldn't change duty status." (§4)
    }
    onDuty = value;
    dutySwitching = false;
    positionAgeSeconds = 0;
    notifyListeners();
    if (value) _maybeDeliverJob();
  }

  // ── Incoming job (§5) ────────────────────────────────────────────────

  /// Demo: going on duty delivers an incoming job shortly (spec §5).
  void _maybeDeliverJob() {
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (!onDuty || activeMission != null) return;
      receiveJob();
    });
  }

  /// Simulates the FCM 'assigned' push landing on this unit.
  void receiveJob() {
    final m = Mission(
      id: 'm-${DateTime.now().millisecondsSinceEpoch % 100000}',
      status: MissionStatus.assigned,
      patient: const PatientProfile(
        name: 'Amina R.',
        bloodType: 'O+',
        allergies: ['Penicillin'],
        conditions: ['Hypertension'],
        contacts: ['Said R. · spouse'],
        contactPhone: '+212661234567',
      ),
      pickupLabel: 'Casablanca · Maârif, Blvd Zerktouni 42',
      pickup: const LatLng(33.5721, -7.5982),
      createdAt: DateTime.now(),
      etaSeconds: 300, // 5 min — replaced by road numbers when OSRM lands
      distanceKm: 1.8,
    );
    activeMission = m;
    jobCountdown = 30;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (activeMission?.status != MissionStatus.assigned) {
        t.cancel();
        return;
      }
      jobCountdown--;
      if (jobCountdown <= 0) {
        t.cancel();
        rejectJob(auto: true);
      } else {
        notifyListeners();
      }
    });
    notifyListeners();
    _fetchPickupRoute(m);
  }

  /// Real OSRM geometry for the pickup leg; ETA/distance update to road
  /// numbers when it lands. Offline → silent straight-line fallback.
  Future<void> _fetchPickupRoute(Mission m) async {
    if (offline) return;
    final route = await RouteService.drivingRoute(unitPosition, m.pickup);
    if (route == null || activeMission?.id != m.id) return;
    m.routeToPickup = route;
    // Road distance replaces the straight-line guess.
    final km = RouteService.totalKm(route);
    m.distanceKm = double.parse(km.toStringAsFixed(1));
    m.etaSeconds = (km * 150).round(); // ~24 km/h Casablanca traffic
    m.legTotalSeconds = m.etaSeconds;
    notifyListeners();
  }

  /// Accept: 1 tap, no confirm (spec §5).
  @override
  void acceptJob() {
    final m = activeMission;
    if (m == null || m.status != MissionStatus.assigned) return;
    _countdownTimer?.cancel();
    m.status = MissionStatus.accepted;
    m.timeline = {...m.timeline, MissionStatus.accepted: DateTime.now()};
    // Dispatch acknowledges in writing (gives the chat badge a first hit).
    _chats.putIfAbsent(m.id, () => []).add(ChatMessage(
      text: 'Copy — proceed to the pickup point.',
      senderRole: 'dispatcher',
      at: DateTime.now(),
    ));
    _startMissionTicker();
    notifyListeners();
  }

  /// 1 Hz demo kinematics: ETA ticks down while moving and the unit marker
  /// advances along the real OSRM road geometry (falls back to a straight
  /// line when the route never loaded).
  void _startMissionTicker() {
    _missionTicker?.cancel();
    _missionTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final m = activeMission;
      if (m == null) {
        _missionTicker?.cancel();
        return;
      }
      final moving = m.status == MissionStatus.accepted ||
          m.status == MissionStatus.enRoute ||
          m.status == MissionStatus.transporting;
      if (moving && m.etaSeconds > 0) {
        m.etaSeconds--;
        final route = m.activeRoute;
        if (route != null && m.legTotalSeconds > 0) {
          // Position = fraction of the leg elapsed; distance = road left.
          final progress =
              1 - (m.etaSeconds / m.legTotalSeconds).clamp(0.0, 1.0);
          unitPosition = RouteService.pointAlong(route, progress);
          m.distanceKm = double.parse(
              (RouteService.totalKm(route) * (1 - progress))
                  .toStringAsFixed(2));
        } else {
          m.distanceKm = double.parse(
              (m.distanceKm - 0.008).clamp(0.0, 99.0).toStringAsFixed(2));
        }
        positionAgeSeconds = 0;
        notifyListeners();
      } else if (m.etaSeconds <= 0 &&
          (m.status == MissionStatus.transporting ||
              m.status == MissionStatus.enRoute)) {
        // Snap to the leg's end once arrived (don't drift mid-block).
        final route = m.activeRoute;
        if (route != null && route.isNotEmpty) {
          unitPosition = route.last;
          m.distanceKm = 0;
          notifyListeners();
        }
      }
    });
  }

  /// Reject: confirm dialog first (patient is waiting). Auto on countdown 0.
  @override
  void rejectJob({bool auto = false}) {
    final m = activeMission;
    if (m == null) return;
    _countdownTimer?.cancel();
    _missionTicker?.cancel();
    activeMission = null;
    if (!auto) {
      _history.insert(
        0,
        MissionHistoryEntry(
          id: m.id,
          route: '${m.pickupLabel.split(',').first} · rejected',
          patientSummary: m.patient.isGuest ? 'Guest' : 'Declined',
          endedAt: DateTime.now(),
          duration: Duration.zero,
        ),
      );
    }
    notifyListeners();
  }

  // ── Lifecycle (§6) ───────────────────────────────────────────────────

  @override
  bool actionBlockedByHospital(MissionStatus s) =>
      s == MissionStatus.onScene && activeMission?.hospitalId == null;

  /// One-tap advance. Server-validated in the real app; demo mirrors the
  /// spec's pending chip + error path.
  @override
  Future<bool> advanceStatus() async {
    final m = activeMission;
    if (m == null || actionBlockedByHospital(m.status)) return false;
    final next = MissionStatus.values[m.status.index + 1];
    m.offlinePending = offline;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (simulateMissionWriteError) {
      m.offlinePending = false;
      notifyListeners();
      return false; // caller shows snackbar (spec §6 error state)
    }
    m.status = next;
    m.timeline = {...m.timeline, next: DateTime.now()};
    m.offlinePending = false;
    // Demo kinematics per phase — road numbers when the route is loaded.
    switch (next) {
      case MissionStatus.enRoute:
        if (m.routeToPickup != null) {
          final km = RouteService.totalKm(m.routeToPickup!);
          m.distanceKm = double.parse(km.toStringAsFixed(1));
          m.etaSeconds = (km * 150).round();
          m.legTotalSeconds = m.etaSeconds;
        } else {
          m.etaSeconds = 240;
          m.distanceKm = 1.2;
        }
      case MissionStatus.onScene:
        m.etaSeconds = 0;
        m.distanceKm = 0;
        unitPosition = m.pickup; // parked at the pickup point
      case MissionStatus.transporting:
        // ETA from the chosen hospital's road leg (prefetched on pick).
        if (m.routeToHospital != null) {
          final km = RouteService.totalKm(m.routeToHospital!);
          m.distanceKm = double.parse(km.toStringAsFixed(1));
          m.etaSeconds = (km * 150).round();
          m.legTotalSeconds = m.etaSeconds;
        } else {
          m.etaSeconds = 480;
          m.distanceKm = 3.0;
        }
      case MissionStatus.atHospital:
        m.etaSeconds = 0;
        m.distanceKm = 0;
      case MissionStatus.resolved:
        _completeMission(m);
      default:
        break;
    }
    notifyListeners();
    return true;
  }

  @override
  void pickHospital(Hospital h) {
    final m = activeMission;
    if (m == null) return;
    m.hospitalId = h.id;
    m.hospitalName = h.name;
    // Pre-compute the transport leg so [Start transport] has honest numbers.
    final km =
        const Distance().as(LengthUnit.Kilometer, m.pickup, h.location);
    m.distanceKm = double.parse(km.toStringAsFixed(1));
    m.etaSeconds = (km * 150).round();
    m.legTotalSeconds = m.etaSeconds;
    notifyListeners();
    _fetchHospitalRoute(m, h);
  }

  /// Real OSRM geometry for the transport leg (silent straight-line
  /// fallback when offline or rate-limited).
  Future<void> _fetchHospitalRoute(Mission m, Hospital h) async {
    if (offline) return;
    final route = await RouteService.drivingRoute(m.pickup, h.location);
    if (route == null || activeMission?.id != m.id) return;
    m.routeToHospital = route;
    final km = RouteService.totalKm(route);
    m.distanceKm = double.parse(km.toStringAsFixed(1));
    m.etaSeconds = (km * 150).round();
    m.legTotalSeconds = m.etaSeconds;
    notifyListeners();
  }

  void _completeMission(Mission m) {
    _missionTicker?.cancel();
    _countdownTimer?.cancel();
    final now = DateTime.now();
    _history.insert(
      0,
      MissionHistoryEntry(
        id: m.id,
        route:
            '${m.pickupLabel.split(',').first} → ${m.hospitalName ?? 'Hospital'}',
        patientSummary: m.patient.isGuest ? 'Guest' : '${m.patient.bloodType ?? '—'} patient',
        endedAt: now,
        duration: now.difference(m.createdAt),
        hospital: m.hospitalName,
        bloodType: m.patient.bloodType,
        isGuest: m.patient.isGuest,
        timeline: Map.of(m.timeline),
      ),
    );
    activeMission = null;
  }

  // ── Chat (§10) ───────────────────────────────────────────────────────

  @override
  Mission? mission(String id) =>
      activeMission != null && activeMission!.id == id ? activeMission : null;

  @override
  List<ChatMessage> messages(String missionId) => _chats[missionId] ?? const [];

  final Map<String, DateTime> _chatOpenedAt = {};

  /// Unread badge: non-crew messages newer than the last time chat was open.
  @override
  int unreadCount(String missionId) {
    final openedAt = _chatOpenedAt[missionId];
    return (_chats[missionId] ?? const [])
        .where((m) =>
            m.senderRole != 'crew' && (openedAt == null || m.at.isAfter(openedAt)))
        .length;
  }

  @override
  void openChat(String missionId) {
    _chatOpenedAt[missionId] = DateTime.now();
    notifyListeners();
  }

  @override
  void sendMessage(String missionId, String text, {bool quick = false}) {
    if (text.trim().isEmpty) return;
    final list = _chats.putIfAbsent(missionId, () => []);
    list.add(ChatMessage(
      text: text.trim(),
      senderRole: 'crew',
      at: DateTime.now(),
      pending: offline,
    ));
    notifyListeners();
  }

  // ── Demo-state setters (state review §14) ────────────────────────────

  @override
  void setOffline(bool v) {
    offline = v;
    notifyListeners();
  }

  @override
  void setGpsLost(bool v) {
    gpsLost = v;
    notifyListeners();
  }

  @override
  void setMissionWriteError(bool v) {
    simulateMissionWriteError = v;
    notifyListeners();
  }

  @override
  void setLoginError(bool v) {
    simulateLoginError = v;
    notifyListeners();
  }

  @override
  void setDutyError(bool v) {
    simulateDutyError = v;
    notifyListeners();
  }

  @override
  void setFleetLoading(bool v) {
    fleetLoading = v;
    notifyListeners();
  }

  @override
  void setFleetError(bool v) {
    fleetError = v;
    notifyListeners();
  }

  @override
  void setVehicleUnmapped(bool v) {
    vehicleUnmapped = v;
    notifyListeners();
  }

  @override
  void setHistoryLoading(bool v) {
    historyLoading = v;
    notifyListeners();
  }

  @override
  void setHistoryError(bool v) {
    historyError = v;
    notifyListeners();
  }

  /// Debug vehicle switcher (existing behavior — kept).
  void switchVehicle(String plate) {
    ambulanceId = plate;
    notifyListeners();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _missionTicker?.cancel();
    super.dispose();
  }

  // ── Seed ─────────────────────────────────────────────────────────────

  void _seed() {
    final now = DateTime.now();

    // m-4471: complete record (every timestamp present).
    final t4471 = <MissionStatus, DateTime>{
      for (final s in MissionStatus.values) s: now.subtract(const Duration(hours: 3)),
    };
    t4471[MissionStatus.assigned] = now.subtract(const Duration(hours: 3, minutes: 22));
    t4471[MissionStatus.accepted] = now.subtract(const Duration(hours: 3, minutes: 21, seconds: 18));
    t4471[MissionStatus.enRoute] = now.subtract(const Duration(hours: 3, minutes: 21));
    t4471[MissionStatus.onScene] = now.subtract(const Duration(hours: 3, minutes: 17));
    t4471[MissionStatus.transporting] = now.subtract(const Duration(hours: 3, minutes: 8));
    t4471[MissionStatus.atHospital] = now.subtract(const Duration(hours: 3, minutes: 1));
    t4471[MissionStatus.resolved] = now.subtract(const Duration(hours: 3));
    _history.add(MissionHistoryEntry(
      id: 'm-4471',
      route: 'Sidi Maârif → Central Hospital',
      patientSummary: 'O+ patient',
      endedAt: now.subtract(const Duration(hours: 3)),
      duration: const Duration(minutes: 18),
      hospital: 'Central Hospital',
      bloodType: 'O+',
      timeline: t4471,
    ));

    // m-4468: older record — some server timestamps missing ("—" per §12).
    final t4468 = <MissionStatus, DateTime>{
      MissionStatus.assigned: now.subtract(const Duration(hours: 5, minutes: 26)),
      MissionStatus.accepted: now.subtract(const Duration(hours: 5, minutes: 25)),
      MissionStatus.onScene: now.subtract(const Duration(hours: 5, minutes: 20)),
      MissionStatus.atHospital: now.subtract(const Duration(hours: 5, minutes: 5)),
      MissionStatus.resolved: now.subtract(const Duration(hours: 5)),
    };
    _history.add(MissionHistoryEntry(
      id: 'm-4468',
      route: 'Bourgogne → Ibn Sina Hospital',
      patientSummary: 'Guest',
      endedAt: now.subtract(const Duration(hours: 5)),
      duration: const Duration(minutes: 24),
      hospital: 'Ibn Sina Hospital',
      isGuest: true,
      timeline: t4468,
    ));

    // m-4460: legacy record — no per-phase timestamps at all.
    _history.add(MissionHistoryEntry(
      id: 'm-4460',
      route: 'Ain Diab → Central Hospital',
      patientSummary: 'A- patient',
      endedAt: now.subtract(const Duration(hours: 8)),
      duration: const Duration(minutes: 12),
      hospital: 'Central Hospital',
      bloodType: 'A-',
    ));

    _chats['m-4471'] = [
      ChatMessage(
          text: 'Patient is conscious, BP 140/90.',
          senderRole: 'crew',
          at: now.subtract(const Duration(hours: 3, minutes: 12))),
      ChatMessage(
          text: 'Copy — Central ER bay 2 is ready.',
          senderRole: 'dispatcher',
          at: now.subtract(const Duration(hours: 3, minutes: 10))),
    ];
  }
}
