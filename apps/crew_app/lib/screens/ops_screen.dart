import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_state.dart';
import '../core/mission_status.dart';
import '../core/tokens.dart';
import '../main.dart' show isTabletLayout;
import '../theme/app_theme.dart';
import '../widgets/atoms.dart';
import 'mission_panel.dart';

/// Ops deck (specs §3–§5) — the crew home.
///
/// Composition (IA §0.5):
/// • phone   → map hero + bottom unit card + incoming banner over the map
/// • tablet  → map hero + persistent right panel (360–400dp); the panel
///             itself becomes the amber incoming-job card.
/// On-duty idle is calm light; the incoming job pulses amber; accepting flips
/// the app into the dark mission theme (hybrid rule).
class OpsScreen extends StatefulWidget {
  final AppState state;
  const OpsScreen({super.key, required this.state});

  @override
  State<OpsScreen> createState() => _OpsScreenState();
}

class _OpsScreenState extends State<OpsScreen> {
  AppState get state => widget.state;
  final MapController _map = MapController();
  MissionStatus? _lastStatus;
  int _lastRouteHash = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tablet = isTabletLayout(context);
    final mission = state.activeMission;

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        // Unmapped vehicle blocks the deck (rare ops/seed error, §3).
        if (state.vehicleUnmapped) return _unmapped(theme);

        final jobIncoming = mission != null &&
            mission.status == MissionStatus.assigned;
        final missionActive = mission != null && !jobIncoming;

        // Re-frame the camera when the phase changes — or when the OSRM
        // geometry lands (routes fetch async, so the first fit may have
        // used the straight-line fallback). Never jumps while idle.
        if (missionActive) {
          final routeHash = Object.hash(
              mission.routeToPickup?.length, mission.routeToHospital?.length);
          if (mission.status != _lastStatus || routeHash != _lastRouteHash) {
            _lastStatus = mission.status;
            _lastRouteHash = routeHash;
            WidgetsBinding.instance.addPostFrameCallback(
                (_) => _fitLeg(mission, tablet));
          }
        } else {
          _lastStatus = null;
          _lastRouteHash = 0;
        }

        final map = _deckMap(theme, mission);

        // ── Tablet: rail is outside; panel docks right ──────────────────
        if (tablet) {
          return Stack(
            children: [
              Positioned.fill(child: map),
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: 380,
                child: jobIncoming
                    ? _MaterialPanel(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: _IncomingJobPanel(state: state),
                        ),
                      )
                    : missionActive
                        ? _MissionPanelShell(
                            tablet: true,
                            child: MissionPanel(state: state, tablet: true))
                        : _MaterialPanel(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: _UnitPanelBody(state: state),
                            ),
                          ),
              ),
            ],
          );
        }

        // ── Phone: banner over map + bottom card ────────────────────────
        return Stack(
          children: [
            Positioned.fill(child: map),
            if (jobIncoming)
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: _IncomingJobBanner(state: state),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: missionActive
                  ? _MissionPanelShell(
                      tablet: false,
                      child: MissionPanel(state: state))
                  : _UnitSheet(state: state),
            ),
          ],
        );
      },
    );
  }

  // ── Map ──────────────────────────────────────────────────────────────

  /// Camera fit for the active leg — unit→pickup (en route) or
  /// pickup→hospital (transporting). Uses full road geometry when loaded.
  /// Degenerate bounds (both ends equal, e.g. parked on scene before a
  /// hospital is picked) fall back to a fixed-zoom center — a zero-area
  /// bounds would blow the camera up and kill the tile layer.
  void _fitLeg(Mission m, bool tablet) {
    if (!state.onDuty) return;
    final toPickup = m.status == MissionStatus.accepted ||
        m.status == MissionStatus.enRoute;
    final route = toPickup ? m.routeToPickup : m.routeToHospital;
    final latLngs = <LatLng>{
      if (route != null && route.isNotEmpty) ...route else ...[
        state.unitPosition,
        if (m.hospitalId != null && !toPickup)
          state.hospitals
              .firstWhere((h) => h.id == m.hospitalId,
                  orElse: () => state.hospitals.first)
              .location
        else
          m.pickup,
      ],
    }.toList(); // dedupe identical endpoints
    try {
      if (latLngs.length == 1) {
        // Parked (on scene, no destination yet) — hold a readable zoom.
        _map.move(latLngs.first, 15.5);
        return;
      }
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(latLngs),
        padding: EdgeInsets.only(
          left: tablet ? 60 : 40,
          top: 60,
          right: tablet ? 440 : 40,
          bottom: tablet ? 60 : 280,
        ),
      ));
    } catch (_) {
      // Map not attached yet (first frame) — ignore.
    }
  }

  Widget _deckMap(ThemeData theme, Mission? mission) {
    if (state.fleetLoading) {
      return Container(
        color: theme.colorScheme.surfaceContainerLowest,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (state.fleetError) {
      return Container(
        color: theme.colorScheme.surfaceContainerLowest,
        alignment: Alignment.center,
        child: EmptyStateBox(
          icon: Icons.map_outlined,
          title: "Couldn't load the map",
          message: 'Your duty status still works — retry when ready.',
          actionLabel: 'Retry',
          onAction: () => state.setFleetError(false),
        ),
      );
    }
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: state.unitPosition,
        initialZoom: 14,
        interactionOptions:
            const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.ambulance.crew_app',
        ),
        // Route polyline: OSRM road geometry when loaded (Step 5 swaps the
        // demo server for the backend's proxy — same data slot), otherwise
        // the straight-line fallback. Phase color per spec §6.
        if (mission != null && mission.status != MissionStatus.assigned)
          PolylineLayer(
            polylines: [
              if (mission.status == MissionStatus.accepted ||
                  mission.status == MissionStatus.enRoute)
                Polyline(
                  points: mission.routeToPickup ??
                      [state.unitPosition, mission.pickup],
                  strokeWidth: 6,
                  color: theme.colorScheme.primary,
                )
              else ...[
                Polyline(
                  points: mission.routeToPickup ??
                      [state.basePosition, mission.pickup],
                  strokeWidth: 6,
                  color: theme.colorScheme.primary.withValues(alpha: 0.45),
                ),
                if (mission.hospitalId != null)
                  Polyline(
                    points: mission.routeToHospital ??
                        [
                          mission.pickup,
                          state.hospitals
                              .firstWhere((h) => h.id == mission.hospitalId,
                                  orElse: () => state.hospitals.first)
                              .location,
                        ],
                    strokeWidth: 6,
                    color: context.statusColor(mission.status),
                  ),
              ],
            ],
          ),
        MarkerLayer(markers: [
          // Base marker (grey).
          Marker(
            point: state.basePosition,
            width: 30,
            height: 30,
            child: Icon(Icons.home_rounded,
                size: 22, color: theme.colorScheme.outline),
          ),
          // Own unit — heading-aware green halo while on duty.
          if (state.onDuty)
            Marker(
              point: state.unitPosition,
              width: 44,
              height: 44,
              child: _UnitMarker(pulse: !state.reduceMotion),
            ),
        ]),
      ],
    );
  }

  Widget _unmapped(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: EmptyStateBox(
            icon: Icons.local_hospital_outlined,
            title: "This account isn't linked to a vehicle",
            message: 'Dispatch assigns units by vehicle. Call dispatch to get '
                'your unit (e.g. AMB-07) assigned to this account.',
            actionLabel: 'Call dispatch',
            onAction: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Dialing dispatch hotline 150…'))),
          ),
        ),
      );
}

// ── Own-unit marker ────────────────────────────────────────────────────

class _UnitMarker extends StatefulWidget {
  final bool pulse;
  const _UnitMarker({this.pulse = true});

  @override
  State<_UnitMarker> createState() => _UnitMarkerState();
}

class _UnitMarkerState extends State<_UnitMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _halo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _halo.repeat();
  }

  @override
  void dispose() {
    _halo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final green = context.statusColor(MissionStatus.resolved);
    return Stack(
      alignment: Alignment.center,
      children: [
        if (widget.pulse)
          AnimatedBuilder(
            animation: _halo,
            builder: (context, _) {
              final t = Curves.easeOut.transform(_halo.value);
              return Container(
                width: 30 + t * 16,
                height: 30 + t * 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: green.withValues(alpha: 0.45 - t * 0.45)),
                ),
              );
            },
          ),
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: green,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(color: green.withValues(alpha: 0.4), blurRadius: 8),
            ],
          ),
          child: const Icon(Icons.local_hospital_rounded,
              size: 13, color: Colors.white),
        ),
      ],
    );
  }
}

// ── Panel/sheet shells ─────────────────────────────────────────────────

class _MaterialPanel extends StatelessWidget {
  final Widget child;
  const _MaterialPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(left: BorderSide(color: theme.colorScheme.outlineVariant)),
        boxShadow: const [
          BoxShadow(color: Color(0x140F172A), blurRadius: 16, offset: Offset(-4, 0)),
        ],
      ),
      child: SafeArea(left: false, child: child),
    );
  }
}

class _UnitSheet extends StatelessWidget {
  final AppState state;
  const _UnitSheet({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        boxShadow: const [
          BoxShadow(color: Color(0x1A0F172A), blurRadius: 16, offset: Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: _UnitPanelBody(state: state),
        ),
      ),
    );
  }
}

/// Dark mission shell — the mission surface (spec §6). On the phone it is a
/// bottom sheet; on the tablet it docks as the right panel. Both wrap the
/// same [MissionPanel] (IA §0.5).
class _MissionPanelShell extends StatelessWidget {
  final Widget child;
  final bool tablet;
  const _MissionPanelShell({required this.child, required this.tablet});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panelDark,
        borderRadius: tablet
            ? null
            : const BorderRadius.vertical(top: Radius.circular(18)),
        border: tablet
            ? Border(left: BorderSide(color: Colors.black.withValues(alpha: 0.25)))
            : null,
      ),
      child: SafeArea(
        top: false,
        left: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }
}

// ── Unit card (idle on/off duty, §3/§4) ────────────────────────────────

class _UnitPanelBody extends StatelessWidget {
  final AppState state;
  const _UnitPanelBody({required this.state});

  String _shiftElapsed() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 8); // demo 08:00
    final d = now.difference(start);
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onDuty = state.onDuty;
    final green = context.statusColor(MissionStatus.resolved);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.offline) ...[
          const OfflineBanner(),
          gapH(8),
        ],
        if (state.gpsLost) ...[
          const GpsLostBanner(),
          gapH(8),
        ],
        if (!state.locationGranted) ...[
          LocationDeniedBanner(
              onOpenSettings: () => state.setLocationGranted(true)),
          gapH(8),
        ],
        // Duty row: chip + switch (first-class, IA §1).
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (onDuty ? green : theme.colorScheme.outlineVariant)
                    .withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppColors.radiusFull),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.dutySwitching)
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: muted),
                    )
                  else
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: onDuty
                            ? green
                            : theme.colorScheme.outline,
                        shape: BoxShape.circle,
                      ),
                    ),
                  gapW(8),
                  Text(
                    state.dutySwitching
                        ? 'SWITCHING…'
                        : onDuty
                            ? 'ON DUTY · ${state.ambulanceId}'
                            : 'OFF DUTY · ${state.ambulanceId}',
                    style: theme.textTheme.labelLarge,
                  ),
                ],
              ),
            ),
            const Spacer(),
            Switch(
              value: onDuty,
              onChanged: state.dutySwitching
                  ? null
                  : (v) async {
                      await state.setOnDuty(v);
                      if (!context.mounted) return;
                      if (state.simulateDutyError) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text(
                                "Couldn't change duty status. Try again.")));
                      }
                    },
            ),
          ],
        ),
        gapH(12),
        // Identity + shift.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(state.crewName, style: theme.textTheme.headlineSmall),
                  gapH(2),
                  Text('Shift 08:00–20:00 · ${state.crewEmail}',
                      style: theme.textTheme.labelSmall),
                ],
              ),
            ),
            if (onDuty) ...[
              Text('Elapsed', style: theme.textTheme.labelSmall),
              gapH(2),
              Text(_shiftElapsed(), style: etaDisplayStyle(size: 18)),
            ],
          ],
        ),
        gapH(8),
        // Freshness / status line.
        Text(
          onDuty
              ? (state.offline
                  ? 'OFFLINE — last position ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}'
                  : 'Position updated ${state.positionAgeSeconds} s ago')
              : "You won't receive jobs while off duty.",
          style: theme.textTheme.labelSmall?.copyWith(color: muted),
        ),
        if (!onDuty) gapH(10),
        gapH(12),
        // Routine row actions.
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Dialing dispatch hotline 150…'))),
              icon: const Icon(Icons.phone_rounded, size: 18),
              label: const Text('Call dispatcher'),
            ),
          ],
        ),
        gapH(10),
        // Primary: duty toggle (outline — routine, not the happy path).
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: state.dutySwitching
                ? null
                : () async {
                    await state.setOnDuty(!onDuty);
                    if (!context.mounted) return;
                    if (state.simulateDutyError) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              "Couldn't change duty status. Try again.")));
                    }
                  },
            icon: state.dutySwitching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(onDuty
                    ? Icons.pause_circle_outline_rounded
                    : Icons.play_circle_outline_rounded),
            label: Text(onDuty ? 'Go off duty' : 'Go on duty'),
          ),
        ),
      ],
    );
  }
}

// ── Incoming job — banner (phone) ──────────────────────────────────────

class _IncomingJobBanner extends StatelessWidget {
  final AppState state;
  const _IncomingJobBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _JobCard(state: state, compact: true, theme: theme);
  }
}

class _IncomingJobPanel extends StatelessWidget {
  final AppState state;
  const _IncomingJobPanel({required this.state});

  @override
  Widget build(BuildContext context) => _JobCard(
      state: state, compact: false, theme: Theme.of(context));
}

/// The amber job card — pulse (phone), countdown ring, distance/ETA readout
/// (Console-influenced, approved), patient line, Accept 2× / Reject 1×.
class _JobCard extends StatefulWidget {
  final AppState state;
  final bool compact;
  final ThemeData theme;
  const _JobCard({required this.state, required this.compact, required this.theme});

  @override
  State<_JobCard> createState() => _JobCardState();
}

class _JobCardState extends State<_JobCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.state.reduceMotion) _pulse.repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _reject() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject this job?'),
        content: const Text(
            'This patient is waiting for another unit. Reject this job?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep job')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirm == true) widget.state.rejectJob();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final state = widget.state;
    final mission = state.activeMission!;
    final amber = context.statusColor(MissionStatus.assigned);
    final reduce = state.reduceMotion || MediaQuery.of(context).disableAnimations;

    final eta = Duration(seconds: mission.etaSeconds);
    final km = mission.distanceKm.toStringAsFixed(1);

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = reduce ? 0.0 : Curves.easeInOut.transform(_pulse.value);
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppColors.radiusMd),
            border: Border.all(color: amber.withValues(alpha: 0.45)),
            boxShadow: [
              BoxShadow(
                color: amber.withValues(alpha: 0.18 + t * 0.22),
                blurRadius: 18 + t * 10,
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: amber.withValues(alpha: 0.14),
                      borderRadius:
                          BorderRadius.circular(AppColors.radiusFull),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications_active_rounded,
                            size: 14, color: amber),
                        gapW(6),
                        Text('NEW EMERGENCY',
                            style: theme.textTheme.labelLarge
                                ?.copyWith(color: amber)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Countdown ring (auto-reject at 0, spec §5).
                  _CountdownRing(
                    seconds: state.jobCountdown,
                    color: state.jobCountdown <= 5
                        ? AppColors.danger
                        : amber,
                  ),
                ],
              ),
              gapH(12),
              // Console-influenced readout row.
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(mission.pickupLabel,
                            style: theme.textTheme.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        gapH(2),
                        Text('Pickup · just now',
                            style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
                  gapW(12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('ETA', style: theme.textTheme.labelSmall),
                      MonoEta(elapsed: eta, size: 26, color: amber),
                    ],
                  ),
                  gapW(14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('DIST', style: theme.textTheme.labelSmall),
                      Text('$km km',
                          style: etaDisplayStyle(
                              size: 26, color: theme.colorScheme.onSurface)),
                    ],
                  ),
                ],
              ),
              gapH(10),
              // Patient line (one row; guest variant per spec §5).
              GestureDetector(
                onTap: () => _showPatientSheet(context),
                child: Row(
                  children: [
                    Icon(Icons.medical_information_outlined,
                        size: 18, color: theme.colorScheme.primary),
                    gapW(8),
                    Expanded(
                      child: Text(
                        mission.patient.summaryLine,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        size: 18, color: theme.colorScheme.outline),
                  ],
                ),
              ),
              gapH(14),
              // Accept 2× (success, no confirm) · Reject 1× (danger, confirm).
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        backgroundColor: AppColors.danger,
                      ),
                      onPressed: _reject,
                      child: const Text('Reject'),
                    ),
                  ),
                  gapW(10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        backgroundColor: AppColors.statusResolved,
                      ),
                      onPressed: state.acceptJob,
                      child: const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showPatientSheet(BuildContext context) {
    final m = widget.state.activeMission!;
    final p = m.patient;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                gapH(14),
                Text(p.isGuest ? 'Guest caller' : (p.name ?? 'Patient'),
                    style: theme.textTheme.headlineSmall),
                gapH(4),
                Text('Profile attached at ${TimeOfDay.now().format(context)} · provided by the patient',
                    style: theme.textTheme.labelSmall),
                gapH(14),
                if (p.isGuest)
                  Text('No medical profile shared',
                      style: theme.textTheme.bodyMedium)
                else ...[
                  Text(p.bloodType ?? 'Blood type not added',
                      style: etaDisplayStyle(size: 28)),
                  gapH(10),
                  Text('Allergies', style: theme.textTheme.labelLarge),
                  gapH(4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: p.allergies.isEmpty
                        ? [const Text('None reported')]
                        : p.allergies
                            .map((a) => Chip(
                                  label: Text(a),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor:
                                      AppColors.danger.withValues(alpha: 0.10),
                                ))
                            .toList(),
                  ),
                  gapH(10),
                  Text('Conditions', style: theme.textTheme.labelLarge),
                  gapH(4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: p.conditions.isEmpty
                        ? [const Text('None reported')]
                        : p.conditions
                            .map((c) => Chip(
                                  label: Text(c),
                                  visualDensity: VisualDensity.compact,
                                ))
                            .toList(),
                  ),
                  gapH(10),
                  Text('Emergency contacts', style: theme.textTheme.labelLarge),
                  gapH(4),
                  if (p.contacts.isEmpty)
                    const Text('None reported')
                  else
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.phone_rounded, size: 20),
                      title: Text(p.contacts.first),
                      subtitle: p.contactPhone != null
                          ? Text(p.contactPhone!)
                          : null,
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Dialing patient contact…'))),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Circular countdown to auto-reject (mono seconds in the middle).
class _CountdownRing extends StatelessWidget {
  final int seconds;
  final Color color;
  const _CountdownRing({required this.seconds, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (seconds / 30).clamp(0.0, 1.0);
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 3,
              backgroundColor: color.withValues(alpha: 0.18),
              color: color,
            ),
          ),
          Text('$seconds',
              style: etaDisplayStyle(size: 15, color: theme.colorScheme.onSurface)),
        ],
      ),
    );
  }
}
