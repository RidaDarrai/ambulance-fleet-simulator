import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'models.dart';

/// The single integration seam between the UI and any data source
/// (docs/design/firebase-backend-handoff.md §2).
///
/// `AppState` holds one of these and mirrors its results into the same public
/// fields the screens already read. Two implementations exist:
///
///  * [DemoRepository] — the in-memory simulation the design was built on.
///  * `FirebaseRepository` — real Firestore/Auth/RTDB (added in a later phase).
///
/// The screens never talk to a repository directly; they only ever see
/// `AppState`, so swapping the implementation is invisible to the UI.
abstract class AppRepository extends ChangeNotifier {
  // ── Fleet & mission data (mirrored by AppState) ─────────────────────
  List<AmbulanceUnit> get units;
  List<Incident> get history;
  Incident? get activeIncident;
  MedicalProfile get medicalProfile;
  LatLng get userLocation;

  // ── Auth ────────────────────────────────────────────────────────────
  bool get isAuthenticated;

  // ── Connectivity & freshness (screen spec §3 states) ────────────────
  bool get offline;
  bool get fleetLoading;
  bool get fleetError;
  DateTime get lastFleetUpdate;
  bool get medicalLoading;

  // ── Submit path (screen spec §5–6) ──────────────────────────────────
  bool get sendFailed;
  LatLng? get lastRequestPickup;
  bool get lastRequestMedical;

  // ── Demo error-simulation toggles (Settings) ────────────────────────
  bool get simulateSubmitError;
  bool get simulateSaveError;

  // ── Auth actions ────────────────────────────────────────────────────
  void signIn();
  void signOut();

  // ── Location & connectivity ─────────────────────────────────────────
  void setUserLocation(LatLng point);
  void setOffline(bool value);

  // ── Fleet ───────────────────────────────────────────────────────────
  void refreshFleet();
  void setFleetError(bool value);

  // ── Incident lifecycle ──────────────────────────────────────────────
  /// [guestName] / [guestPhone] are the guest callback details the request
  /// flow collects for unauthenticated users (spec §5) — the backend stores
  /// them so dispatch can reach a guest back. Repositories remember the last
  /// values so a retry (which re-sends without them) keeps them.
  void triggerRequest(
      {LatLng? pickup, bool? medicalAttached, String? guestName, String? guestPhone});
  void cancelRequest();
  void clearActiveIncident();

  // ── Medical profile (screen spec §11–12) ────────────────────────────
  bool setBloodType(String? value);
  bool setAllergies(List<String> value);
  bool setConditions(List<String> value);
  bool addContact(EmergencyContact contact);
  bool updateContact(EmergencyContact contact);
  bool removeContact(EmergencyContact contact);
  void resetMedicalProfile();

  // ── Demo error-simulation setters ───────────────────────────────────
  void setSimulateSubmitError(bool value);
  void setSimulateSaveError(bool value);
}
