import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'mission_status.dart';
import 'models.dart';

/// The single integration seam between the crew UI and any data source —
/// the same pattern the patient app uses (docs/design/firebase-backend-handoff.md §2).
///
/// `AppState` holds one of these and mirrors its results into the same public
/// fields the screens already read. Two implementations exist:
///
///  * [DemoRepository] — the in-memory simulation the design was built on.
///  * `FirebaseRepository` — real Firestore/Auth/RTDB (added in a later phase).
///
/// The screens never talk to a repository directly; they only ever see
/// `AppState`, so swapping the implementation is invisible to the UI.
abstract class CrewRepository extends ChangeNotifier {
  // ── Identity (login §1) ──────────────────────────────────────────────
  bool get isSignedIn;
  String get crewName;
  String get crewEmail;
  String get ambulanceId;
  bool get sessionExpired;

  /// Demo accepts the seeded crew credentials; Firebase signs in for real.
  Future<bool> signIn(String email, String password);
  void signOut();
  bool get canSignOut;
  void expireSession();

  // ── Duty (§3/§4) ─────────────────────────────────────────────────────
  bool get onDuty;
  bool get dutySwitching;
  Future<void> setOnDuty(bool value);

  // ── Deck data states (§3) ────────────────────────────────────────────
  bool get fleetLoading;
  bool get fleetError; // map error card + Retry
  bool get vehicleUnmapped; // account not linked to a vehicle

  // ── Cross-cutting connectivity (§14) ─────────────────────────────────
  bool get offline;
  bool get gpsLost;

  // ── Missions (§5/§6) ─────────────────────────────────────────────────
  Mission? get activeMission;

  /// Seconds left on the incoming-job auto-reject countdown (§5).
  int get jobCountdown;
  bool get simulateMissionWriteError;
  bool get simulateDutyError;
  bool get simulateLoginError;

  // ── Directory data ───────────────────────────────────────────────────
  List<Hospital> get hospitals;
  LatLng get unitPosition;
  LatLng get basePosition;
  int get positionAgeSeconds;

  // ── History (§11) ────────────────────────────────────────────────────
  List<MissionHistoryEntry> get history;
  bool get historyLoading;
  bool get historyError;

  // ── Mission lifecycle actions ────────────────────────────────────────
  void acceptJob();
  void rejectJob({bool auto});
  Future<bool> advanceStatus();
  bool actionBlockedByHospital(MissionStatus status);
  void pickHospital(Hospital h);

  /// Lookup for a chat opened from a notification/deep link. History
  /// missions are summaries, so only the active mission resolves.
  Mission? mission(String id);

  // ── Chat (§10) ───────────────────────────────────────────────────────
  List<ChatMessage> messages(String missionId);
  int unreadCount(String missionId);
  void openChat(String missionId);
  void sendMessage(String missionId, String text, {bool quick});

  // ── Demo-state setters (state review §14) ────────────────────────────
  // In Firebase these are inert or driven by real connectivity; the demo
  // repository uses them to review spec'd UI states on demand.
  void setOffline(bool value);
  void setGpsLost(bool value);
  void setMissionWriteError(bool value);
  void setLoginError(bool value);
  void setDutyError(bool value);
  void setFleetLoading(bool value);
  void setFleetError(bool value);
  void setVehicleUnmapped(bool value);
  void setHistoryLoading(bool value);
  void setHistoryError(bool value);
}
