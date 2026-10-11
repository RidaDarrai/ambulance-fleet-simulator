import 'package:flutter/material.dart';
import 'tokens.dart';

/// Mission lifecycle shared end-to-end (baseline-report.md §4):
/// pending → dispatched → enRoute → onScene → transporting → atHospital → resolved.
enum MissionStatus {
  pending,
  dispatched,
  enRoute,
  onScene,
  transporting,
  atHospital,
  resolved;

  /// 1-word-ish label used in chips, strips and timeline.
  String get label => switch (this) {
        pending => 'Pending',
        dispatched => 'Dispatched',
        enRoute => 'En route',
        onScene => 'On scene',
        transporting => 'Transporting',
        atHospital => 'At hospital',
        resolved => 'Resolved',
      };

  /// Status color for light theme.
  Color light() => switch (this) {
        pending => AppColors.statusPending,
        dispatched => AppColors.statusDispatched,
        enRoute => AppColors.statusEnRoute,
        onScene => AppColors.statusOnScene,
        transporting => AppColors.statusTransporting,
        atHospital => AppColors.statusAtHospital,
        resolved => AppColors.statusResolved,
      };

  /// Status color for dark theme.
  Color dark() => switch (this) {
        pending => AppColors.statusPendingDark,
        dispatched => AppColors.statusDispatchedDark,
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

/// Folds the backend's mission statuses onto the design's locked 7.
///
/// The backend (dispatcher/crew) uses `requested`, `assigned`, `accepted`,
/// `enRoute`, `onScene`, `transporting`, `atHospital`, `resolved` — 8 states.
/// The design locks 7 and asserts there are exactly 7. `assigned` and
/// `accepted` are both dispatch-phase from the patient's view, so they fold to
/// `dispatched`; `requested` maps to the design's `pending`. Anything unknown
/// degrades to `pending` rather than crashing (handoff §3).
MissionStatus mapBackendStatus(String s) => switch (s) {
      'requested' => MissionStatus.pending,
      'assigned' || 'accepted' => MissionStatus.dispatched,
      'enRoute' => MissionStatus.enRoute,
      'onScene' => MissionStatus.onScene,
      'transporting' => MissionStatus.transporting,
      'atHospital' => MissionStatus.atHospital,
      'resolved' => MissionStatus.resolved,
      _ => MissionStatus.pending,
    };