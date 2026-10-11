import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'app_repository.dart';
import 'demo_repository.dart';
import 'models.dart';

export 'models.dart'; // re-export domain models so screens keep compiling

/// Client-side app state: a thin adapter over an [AppRepository].
///
/// Every screen does `ListenableBuilder(listenable: state, ...)` and reads
/// fields like `state.units` / `state.activeIncident`, and calls actions like
/// `state.triggerRequest()`. [AppState] keeps that exact public API, but the
/// *data* now comes from a pluggable repository:
///
/// ```
/// screens ──> AppState ──> AppRepository
///                             ├── DemoRepository   (in-memory sim, default)
///                             └── FirebaseRepository (real backend, later)
/// ```
///
/// UI *preferences* (theme, onboarding, notification toggles, privacy) stay
/// here because they aren't repository concerns. [AppState] listens to the
/// repository and re-notifies, so the screens see no difference.
class AppState extends ChangeNotifier {
  AppRepository _repo;

  AppState({AppRepository? repository})
      : _repo = repository ?? DemoRepository() {
    _repo.addListener(_onRepoChanged);
  }

  void _onRepoChanged() => notifyListeners();

  /// Swap the data source at runtime (Settings "State (demo)" switch).
  /// Defaults to [DemoRepository] so UI walkthroughs work without a backend.
  void useRepository(AppRepository next) {
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
  List<AmbulanceUnit> get units => _repo.units;
  List<Incident> get history => _repo.history;
  Incident? get activeIncident => _repo.activeIncident;
  MedicalProfile get medicalProfile => _repo.medicalProfile;
  LatLng get userLocation => _repo.userLocation;

  bool get isAuthenticated => _repo.isAuthenticated;

  bool get offline => _repo.offline;
  bool get fleetLoading => _repo.fleetLoading;
  bool get fleetError => _repo.fleetError;
  DateTime get lastFleetUpdate => _repo.lastFleetUpdate;
  bool get medicalLoading => _repo.medicalLoading;

  bool get sendFailed => _repo.sendFailed;
  LatLng? get lastRequestPickup => _repo.lastRequestPickup;
  bool get lastRequestMedical => _repo.lastRequestMedical;

  bool get simulateSubmitError => _repo.simulateSubmitError;
  bool get simulateSaveError => _repo.simulateSaveError;

  // ── Data actions delegated to the repository ────────────────────────
  void signIn() => _repo.signIn();
  void signOut() => _repo.signOut();
  void setUserLocation(LatLng point) => _repo.setUserLocation(point);
  void setOffline(bool value) => _repo.setOffline(value);
  void refreshFleet() => _repo.refreshFleet();
  void setFleetError(bool value) => _repo.setFleetError(value);
  void setSimulateSubmitError(bool value) =>
      _repo.setSimulateSubmitError(value);
  void setSimulateSaveError(bool value) => _repo.setSimulateSaveError(value);

  void triggerRequest(
          {LatLng? pickup,
          bool? medicalAttached,
          String? guestName,
          String? guestPhone}) =>
      _repo.triggerRequest(
          pickup: pickup,
          medicalAttached: medicalAttached,
          guestName: guestName,
          guestPhone: guestPhone);
  void cancelRequest() => _repo.cancelRequest();
  void clearActiveIncident() => _repo.clearActiveIncident();

  bool setBloodType(String? value) => _repo.setBloodType(value);
  bool setAllergies(List<String> value) => _repo.setAllergies(value);
  bool setConditions(List<String> value) => _repo.setConditions(value);
  bool addContact(EmergencyContact contact) => _repo.addContact(contact);
  bool updateContact(EmergencyContact contact) => _repo.updateContact(contact);
  bool removeContact(EmergencyContact contact) =>
      _repo.removeContact(contact);
  void resetMedicalProfile() => _repo.resetMedicalProfile();

  // ── App preferences (not repository concerns) ───────────────────────
  bool onboardingDone = false;
  bool reduceMotion = false;
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

  // ── Preference actions ──────────────────────────────────────────────
  void completeOnboarding() {
    onboardingDone = true;
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

  void setLocationGranted(bool value) {
    locationGranted = value;
    notifyListeners();
  }

  /// Requests the OS/browser location permission (the primer has already
  /// explained *why* before this point) and, if granted, replaces the demo
  /// pin with the real device position. Returns whether we ended up with a
  /// real fix; on denial the pin stays wherever it was (manual long-press
  /// still works) and the UI's permission-denied states kick in.
  Future<bool> useMyLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        locationGranted = false;
        notifyListeners();
        return false;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high),
      );
      locationGranted = true;
      _repo.setUserLocation(LatLng(pos.latitude, pos.longitude));
      return true;
    } catch (_) {
      // Web user dismissed the browser prompt, or location services off.
      locationGranted = false;
      notifyListeners();
      return false;
    }
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

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    _repo.dispose();
    super.dispose();
  }
}
