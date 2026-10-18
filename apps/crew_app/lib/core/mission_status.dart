import 'package:flutter/material.dart';
import 'tokens.dart';

/// Crew-facing mission lifecycle (backend truth, `crew_service.dart`):
/// assigned → accepted → enRoute → onScene → transporting → atHospital → resolved.
/// Reject returns the mission to `requested` (no crew attached) — modeled as
/// "no active mission" on the client.
///
/// Colors reuse the shared token palette: `assigned` = amber (was patient
/// `pending`), `accepted` = blue (was patient `dispatched`).
enum MissionStatus {
  assigned,
  accepted,
  enRoute,
  onScene,
  transporting,
  atHospital,
  resolved;

  /// 1-word-ish label used in chips, strips and timeline.
  String get label => switch (this) {
        assigned => 'Incoming',
        accepted => 'Accepted',
        enRoute => 'En route',
        onScene => 'On scene',
        transporting => 'Transporting',
        atHospital => 'At hospital',
        resolved => 'Completed',
      };

  /// Header strip label (status strip per direction board).
  String get stripLabel => switch (this) {
        assigned => 'INCOMING EMERGENCY',
        accepted => 'ACCEPTED — READY',
        enRoute => 'EN ROUTE TO PATIENT',
        onScene => 'ON SCENE',
        transporting => 'TRANSPORTING TO HOSPITAL',
        atHospital => 'AT HOSPITAL',
        resolved => 'COMPLETED',
      };

  /// The 5 mission-progress dots run accepted → atHospital; assigned and
  /// resolved sit outside the strip (pre/post mission).
  int? get stepIndex => switch (this) {
        assigned => null,
        accepted => 0,
        enRoute => 1,
        onScene => 2,
        transporting => 3,
        atHospital => 4,
        resolved => null,
      };

  /// The single next action label for this phase (spec §6).
  String get actionLabel => switch (this) {
        assigned => 'Accept job',
        accepted => 'Start en route',
        enRoute => 'Arrived on scene',
        onScene => 'Start transport',
        transporting => 'Arrived at hospital',
        atHospital => 'Complete mission',
        resolved => 'Mission completed',
      };

  bool get isActive => this != resolved;

  /// Status color for light theme.
  Color light() => switch (this) {
        assigned => AppColors.statusPending,
        accepted => AppColors.statusDispatched,
        enRoute => AppColors.statusEnRoute,
        onScene => AppColors.statusOnScene,
        transporting => AppColors.statusTransporting,
        atHospital => AppColors.statusAtHospital,
        resolved => AppColors.statusResolved,
      };

  /// Status color for dark theme.
  Color dark() => switch (this) {
        assigned => AppColors.statusPendingDark,
        accepted => AppColors.statusDispatchedDark,
        enRoute => AppColors.statusEnRouteDark,
        onScene => AppColors.statusOnSceneDark,
        transporting => AppColors.statusTransportingDark,
        atHospital => AppColors.statusAtHospitalDark,
        resolved => AppColors.statusResolvedDark,
      };
}

extension MissionStatusBuildContextX on BuildContext {
  /// Picks the status color matching the surrounding brightness.
  Color statusColor(MissionStatus status) =>
      Theme.of(this).brightness == Brightness.dark
          ? status.dark()
          : status.light();
}
