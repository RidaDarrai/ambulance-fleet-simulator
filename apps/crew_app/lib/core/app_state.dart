import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'crew_repository.dart';
import 'demo_repository.dart';
import 'mission_status.dart';
import 'models.dart';

export 'models.dart'; // re-export domain models so screens keep compiling

/// Client-side app state: a thin adapter over a [CrewRepository].
///
/// Every screen does `ListenableBuilder(listenable: state, ...)` and reads
/// fields like `state.activeMission` / `state.onDuty`, and calls actions like
/// `state.acceptJob()`. [AppState] keeps that exact public API, but the *data*
/// now comes from a pluggable repository:
///
/// ```
/// screens ──> AppState ──> CrewRepository
///                             ├── DemoRepository    (in-memory sim, default)
///                             └── FirebaseRepository (real backend, later)
/// ```
///
/// UI *preferences* (location primer, reduce-motion, notification toggles)
/// stay here because they aren't repository concerns. [AppState] listens to
/// the repository and re-notifies, so the screens see no difference.
class AppState extends ChangeNotifier {
  CrewRepository _repo;

  AppState({CrewRepository? repository})
      : _repo = repository ?? DemoRepository() {
    _repo.addListener(_onRepoChanged);
  }

  void _onRepoChanged() => notifyListeners();

  /// Swap the data source at runtime (Account "State (demo)" switch).
  /// Defaults to [DemoRepository] so UI walkthroughs work without a backend.
  void useRepository(CrewRepository next) {
    if (identical(next, _repo)) return;
    _repo.removeListener(_onRepoChanged);
    _repo.dispose();
    _repo = next;
    _repo.addListener(_onRepoChanged);
    notifyListeners();
  }

  /// Whether we're currently on the in-memory demo data source.
  bool get isDemo => _repo is DemoRepository;

  // ── Data mirrored from the repository ───────────────────────────────
  bool get isSignedIn => _repo.isSignedIn;
  String get crewName => _repo.crewName;
  String get crewEmail => _repo.crewEmail;
  String get ambulanceId => _repo.ambulanceId;
  bool get sessionExpired => _repo.sessionExpired;

  bool get onDuty => _repo.onDuty;
  bool get dutySwitching => _repo.dutySwitching;

  bool get fleetLoading => _repo.fleetLoading;
  bool get fleetError => _repo.fleetError;
  bool get vehicleUnmapped => _repo.vehicleUnmapped;

  bool get offline => _repo.offline;
  bool get gpsLost => _repo.gpsLost;

  Mission? get activeMission => _repo.activeMission;
  int get jobCountdown => _repo.jobCountdown;
  bool get simulateMissionWriteError => _repo.simulateMissionWriteError;
  bool get simulateDutyError => _repo.simulateDutyError;
  bool get simulateLoginError => _repo.simulateLoginError;

  List<Hospital> get hospitals => _repo.hospitals;
  LatLng get unitPosition => _repo.unitPosition;
  LatLng get basePosition => _repo.basePosition;
  int get positionAgeSeconds => _repo.positionAgeSeconds;

  List<MissionHistoryEntry> get history => _repo.history;
  bool get historyLoading => _repo.historyLoading;
  bool get historyError => _repo.historyError;

  bool get canSignOut => _repo.canSignOut;

  // ── Data actions delegated to the repository ────────────────────────
  Future<bool> signIn(String email, String password) =>
      _repo.signIn(email, password);
  void signOut() => _repo.signOut();
  void expireSession() => _repo.expireSession();
  Future<void> setOnDuty(bool value) => _repo.setOnDuty(value);

  void acceptJob() => _repo.acceptJob();
  void rejectJob({bool auto = false}) => _repo.rejectJob(auto: auto);
  Future<bool> advanceStatus() => _repo.advanceStatus();
  bool actionBlockedByHospital(MissionStatus status) =>
      _repo.actionBlockedByHospital(status);
  void pickHospital(Hospital h) => _repo.pickHospital(h);

  Mission? mission(String id) => _repo.mission(id);

  List<ChatMessage> messages(String missionId) => _repo.messages(missionId);
  int unreadCount(String missionId) => _repo.unreadCount(missionId);
  void openChat(String missionId) => _repo.openChat(missionId);
  void sendMessage(String missionId, String text, {bool quick = false}) =>
      _repo.sendMessage(missionId, text, quick: quick);

  // ── Demo-state setters (state review §14) ────────────────────────────
  void setOffline(bool value) => _repo.setOffline(value);
  void setGpsLost(bool value) => _repo.setGpsLost(value);
  void setMissionWriteError(bool value) => _repo.setMissionWriteError(value);
  void setLoginError(bool value) => _repo.setLoginError(value);
  void setDutyError(bool value) => _repo.setDutyError(value);
  void setFleetLoading(bool value) => _repo.setFleetLoading(value);
  void setFleetError(bool value) => _repo.setFleetError(value);
  void setVehicleUnmapped(bool value) => _repo.setVehicleUnmapped(value);
  void setHistoryLoading(bool value) => _repo.setHistoryLoading(value);
  void setHistoryError(bool value) => _repo.setHistoryError(value);

  // ── App preferences (not repository concerns) ───────────────────────
  bool reduceMotion = false;
  bool soundEnabled = true;
  bool respectQuietHours = false;

  // ── Pre-permission primers (screen spec §2) ─────────────────────────
  bool locationPrimerShown = false;
  bool locationGranted = true; // demo default; denied strip is togglable

  void completeLocationPrimer({required bool granted}) {
    locationPrimerShown = true;
    locationGranted = granted;
    notifyListeners();
  }

  void setLocationGranted(bool value) {
    locationGranted = value;
    notifyListeners();
  }

  void setReduceMotion(bool value) {
    reduceMotion = value;
    notifyListeners();
  }

  void setSound(bool value) {
    soundEnabled = value;
    notifyListeners();
  }

  void setRespectQuietHours(bool value) {
    respectQuietHours = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    _repo.dispose();
    super.dispose();
  }
}
