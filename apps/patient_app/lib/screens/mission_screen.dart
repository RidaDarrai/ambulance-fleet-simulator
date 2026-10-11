import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_state.dart';
import '../core/mission_status.dart';
import '../core/tokens.dart';
import '../theme/app_theme.dart';
import '../widgets/atoms.dart';
import 'medical_profile_screen.dart';

/// /mission/:id — live tracking (screen spec §7) + mission summary (§8).
///
/// Hybrid lock: dark Mission-Critical HUD from `dispatched` through
/// `atHospital`; at `resolved` the route re-renders in the calm light theme.
/// States: loading (skeleton ETA/card) · error (position stale + Retry) ·
/// offline (frozen route, ETA unavailable, comms/cancel disabled) ·
/// permission-denied (your pin hidden, saved-address note).
class MissionScreen extends StatefulWidget {
  final AppState state;
  const MissionScreen({super.key, required this.state});

  @override
  State<MissionScreen> createState() => _MissionScreenState();
}

class _MissionScreenState extends State<MissionScreen> {
  final MapController _map = MapController();
  final DraggableScrollableController _sheetCtl =
      DraggableScrollableController();

  bool _booting = true; // first GPS ping skeleton (§7 loading, ≤2 s)
  int? _rating; // §8 optional 1–5
  double _lastSnapped = 0.34;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _booting = false);
    });
    _sheetCtl.addListener(_reframeOnSnap);
  }

  @override
  void dispose() {
    _sheetCtl.removeListener(_reframeOnSnap);
    _sheetCtl.dispose();
    super.dispose();
  }

  /// Map re-frames to the mission bounds whenever the sheet settles on a
  /// snap point (§7 gestures).
  void _reframeOnSnap() {
    if (!_sheetCtl.isAttached) return;
    final size = _sheetCtl.size;
    for (final snap in const [0.34, 0.5, 0.8]) {
      if ((size - snap).abs() < 0.01 && (snap - _lastSnapped).abs() > 0.01) {
        _lastSnapped = snap;
        _frameMission();
        return;
      }
    }
  }

  void _frameMission() {
    final inc = state.activeIncident;
    if (inc == null) return;
    final unit = _unitOf(inc);
    final bounds = LatLngBounds.fromPoints([
      inc.pickup,
      if (unit != null) unit.position,
      if (inc.status == MissionStatus.transporting ||
          inc.status == MissionStatus.atHospital)
        inc.hospital,
    ]);
    _map.fitCamera(CameraFit.bounds(
      bounds: bounds,
      padding: const EdgeInsets.fromLTRB(24, 120, 24, 300),
    ));
  }

  AmbulanceUnit? _unitOf(Incident inc) => inc.unitId == null
      ? null
      : state.units.where((u) => u.id == inc.unitId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final inc = state.activeIncident;
        if (inc == null) {
          // Mission already closed — nothing to show.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).pop();
          });
          return const Scaffold(body: SizedBox.shrink());
        }
        final resolved = inc.status == MissionStatus.resolved;
        return resolved
            ? _buildSummary(context, inc) // §8 — calm light theme
            : _buildMissionHud(context, inc); // §7 — dark mission HUD
      },
    );
  }

  // ── §7 Live mission tracking (dark) ────────────────────────────────

  Widget _buildMissionHud(BuildContext context, Incident inc) {
    final unit = _unitOf(inc);
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Stack(
        children: [
          _MissionMap(
            map: _map,
            inc: inc,
            unit: unit,
            offline: state.offline,
            showMyPin: state.locationGranted,
          ),
          // Status band: full-width, status color + icon + word (spec §7).
          _StatusBand(inc: inc, unit: unit, offline: state.offline),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.topLeft,
                child: _GlassButton(
                  icon: Icons.arrow_back_rounded,
                  // Back minimizes to a banner — it never cancels (spec §7).
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DraggableScrollableSheet(
              controller: _sheetCtl,
              initialChildSize: 0.34,
              minChildSize: 0.22,
              maxChildSize: 0.8,
              snap: true,
              snapSizes: const [0.34, 0.5, 0.8],
              builder: (context, scrollController) => _MissionSheet(
                state: state,
                inc: inc,
                unit: unit,
                scrollController: scrollController,
                booting: _booting,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── §8 Mission summary (light, calm) ───────────────────────────────

  Widget _buildSummary(BuildContext context, Incident inc) {
    final theme = Theme.of(context);
    final unit = _unitOf(inc);
    final resolvedAt = inc.statusTimes[MissionStatus.resolved] ?? DateTime.now();
    final total = resolvedAt.difference(inc.createdAt);
    final totalLabel = total.inMinutes >= 1
        ? '${total.inMinutes} min'
        : '${total.inSeconds} s';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            gapH(16),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.statusResolved.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  size: 34, color: AppColors.statusResolved),
            ),
            gapH(16),
            Text('Mission complete', style: theme.textTheme.headlineLarge),
            gapH(4),
            Text('Help arrived at ${_hhmm(resolvedAt)}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            gapH(20),
            // Recap card (spec §8).
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppColors.radiusMd),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _recapRow(theme, 'Unit', unit?.callsign ?? '—'),
                  _recapRow(theme, 'Crew',
                      unit == null ? '—' : 'Crew of ${unit.crewSize}'),
                  _recapRow(theme, 'Total time', totalLabel, mono: true),
                  Divider(color: theme.colorScheme.outlineVariant, height: 20),
                  for (final s in MissionStatus.values)
                    if (inc.statusTimes[s] != null)
                      _recapRow(theme, s.label, _hhmm(inc.statusTimes[s]!),
                          mono: true),
                ],
              ),
            ),
            gapH(20),
            // Optional rating (spec §8).
            Text('How was the response?', style: theme.textTheme.headlineMedium),
            gapH(2),
            Text('Rate the response (optional)',
                style: theme.textTheme.labelSmall),
            gapH(10),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _RatingDot(
                      value: i,
                      selected: (_rating ?? 0) >= i,
                      onTap: () => setState(() => _rating = i),
                    ),
                  ),
              ],
            ),
            gapH(20),
            FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              onPressed: () {
                state.clearActiveIncident();
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
              child: const Text('Done'),
            ),
            gapH(4),
            if (state.isAuthenticated)
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => MedicalProfileScreen(state: state)),
                ),
                child: const Text('Update your medical profile'),
              ),
            if (state.offline)
              Center(
                child: Text('Saved on this device',
                    style: theme.textTheme.labelSmall),
              ),
          ],
        ),
      ),
    );
  }

  Widget _recapRow(ThemeData theme, String label, String value,
          {bool mono = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
            Text(value,
                style: mono
                    ? etaDisplayStyle(size: 14)
                    : theme.textTheme.bodyMedium),
          ],
        ),
      );

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// 1–5 rating dot (spec §8) — token `color.status.resolved` when selected.
class _RatingDot extends StatelessWidget {
  final int value;
  final bool selected;
  final VoidCallback onTap;
  const _RatingDot({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Rate $value of 5',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.statusResolved.withValues(alpha: 0.14)
                : theme.colorScheme.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? AppColors.statusResolved
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Center(
            child: Text('$value',
                style: selected
                    ? etaDisplayStyle(size: 16, color: AppColors.statusResolved)
                    : theme.textTheme.bodyLarge),
          ),
        ),
      ),
    );
  }
}

// ── §7 pieces ──────────────────────────────────────────────────────────

/// Full-width status band: status color + icon + word (spec §7).
class _StatusBand extends StatelessWidget {
  final Incident inc;
  final AmbulanceUnit? unit;
  final bool offline;
  const _StatusBand({required this.inc, required this.unit, required this.offline});

  String get _word => switch (inc.status) {
        MissionStatus.pending => 'In the queue',
        MissionStatus.dispatched => 'Dispatched',
        // "Arriving soon" once the crew is within a minute (spec §7).
        MissionStatus.enRoute =>
          inc.etaSeconds > 0 && inc.etaSeconds <= 60 ? 'Arriving soon' : 'En route',
        MissionStatus.onScene => 'On scene',
        MissionStatus.transporting => 'Transporting to $kHospitalName',
        MissionStatus.atHospital => 'At hospital',
        MissionStatus.resolved => 'Resolved',
      };

  IconData get _icon => switch (inc.status) {
        MissionStatus.pending => Icons.hourglass_top_rounded,
        MissionStatus.dispatched => Icons.radio_rounded,
        MissionStatus.enRoute => Icons.navigation_rounded,
        MissionStatus.onScene => Icons.location_pin,
        MissionStatus.transporting => Icons.local_hospital_rounded,
        MissionStatus.atHospital => Icons.apartment_rounded,
        MissionStatus.resolved => Icons.check_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final color = context.statusColor(inc.status);
    final unitLine = unit == null
        ? 'Finding the nearest unit'
        : '${unit!.callsign} is on the way';
    return Material(
      color: color.withValues(alpha: 0.16),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(56, 8, 12, 10),
          child: Row(
            children: [
              Icon(_icon, size: 18, color: color),
              gapW(10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _word.toUpperCase(),
                      style: const TextStyle(
                          color: AppColors.textInverse,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.06),
                    ),
                    Text(
                      offline ? 'Offline — last position 40 s ago' : unitLine,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              StatusChip(status: inc.status),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissionMap extends StatelessWidget {
  final MapController map;
  final Incident inc;
  final AmbulanceUnit? unit;
  final bool offline;
  final bool showMyPin;

  const _MissionMap({
    required this.map,
    required this.inc,
    required this.unit,
    required this.offline,
    required this.showMyPin,
  });

  @override
  Widget build(BuildContext context) {
    final color = context.statusColor(inc.status);
    final markers = <Marker>[
      if (unit != null)
        Marker(
          point: unit!.position,
          width: 26,
          height: 26,
          child: _GlowMarker(color: color),
        ),
      // Your pin hidden when location is off (spec §7 permission-denied).
      if (showMyPin)
        Marker(
          point: inc.pickup,
          width: 16,
          height: 16,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 3),
            ),
          ),
        ),
      if (inc.status == MissionStatus.transporting ||
          inc.status == MissionStatus.atHospital)
        Marker(
          point: inc.hospital,
          width: 18,
          height: 18,
          child: Container(
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Text('H',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
        ),
    ];

    final routeTarget = switch (inc.status) {
      MissionStatus.transporting || MissionStatus.atHospital => inc.hospital,
      _ => inc.pickup,
    };

    return SizedBox.expand(
      child: ColoredBox(
        color: AppColors.backgroundDark,
        child: FlutterMap(
          mapController: map,
          options: MapOptions(
            initialCenter: unit == null
                ? inc.pickup
                : LatLng(
                    (unit!.position.latitude + inc.pickup.latitude) / 2,
                    (unit!.position.longitude + inc.pickup.longitude) / 2,
                  ),
            initialZoom: 13,
            backgroundColor: AppColors.backgroundDark,
          ),
          children: [
            if (!offline)
              TileLayer(
                urlTemplate: kOsmTileUrl,
                userAgentPackageName: 'com.ambulance.patient_app',
              ),
            // Offline: polyline frozen at the last known ping (spec §7).
            if (unit != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [unit!.position, routeTarget],
                    strokeWidth: 6,
                    color: color,
                  ),
                ],
              ),
            MarkerLayer(markers: markers),
          ],
        ),
      ),
    );
  }
}

class _GlowMarker extends StatelessWidget {
  final Color color;
  const _GlowMarker({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.5),
              blurRadius: 10,
              spreadRadius: 4),
        ],
      ),
      child: const Text('✚',
          style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1)),
    );
  }
}

/// Draggable sheet: ETA hero, crew card, timeline stepper, medical chip,
/// persistent Call dispatcher + Cancel request (spec §7).
class _MissionSheet extends StatelessWidget {
  final AppState state;
  final Incident inc;
  final AmbulanceUnit? unit;
  final ScrollController scrollController;
  final bool booting;

  const _MissionSheet({
    required this.state,
    required this.inc,
    required this.unit,
    required this.scrollController,
    required this.booting,
  });

  double? get _distanceKm {
    if (unit == null) return null;
    return const Distance().as(LengthUnit.Kilometer, unit!.position, inc.pickup);
  }

  @override
  Widget build(BuildContext context) {
    final color = context.statusColor(inc.status);
    final offline = state.offline;
    final stale = state.fleetError;
    final etaAvailable = inc.etaSeconds > 0 && !offline;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.panelDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppColors.radiusLg)),
        boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 18)],
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.borderDark,
                borderRadius: BorderRadius.circular(AppColors.radiusFull),
              ),
            ),
          ),
          if (stale) ...[
            // Position error state (spec §7).
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.dangerSurface,
                borderRadius: BorderRadius.circular(AppColors.radiusMd),
                border: Border.all(color: AppColors.dangerBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      size: 18, color: AppColors.danger),
                  gapW(10),
                  Expanded(
                    child: Text(
                      "Couldn't update the crew position. Last update 40 s ago.",
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: state.refreshFleet,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
            gapH(12),
          ],
          // ETA hero (spec §7): mono 32 + sublabel.
          if (booting) ...[
            const SkeletonBlock(width: 160, height: 40),
            gapH(8),
            const SkeletonBlock(width: double.infinity, height: 96),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        etaAvailable ? 'Arriving in' : 'ETA',
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 11),
                      ),
                      MonoEta(
                        elapsed: etaAvailable
                            ? Duration(seconds: inc.etaSeconds)
                            : null,
                        size: 32,
                        color: color,
                      ),
                      if (!etaAvailable)
                        Text(
                          offline
                              ? 'ETA unavailable offline'
                              : 'ETA not available yet',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 11),
                        ),
                      gapH(2),
                      Text(
                        [
                          if (unit != null) 'Unit ${unit!.callsign}',
                          if (_distanceKm != null)
                            '${_distanceKm!.toStringAsFixed(1)} km',
                        ].join(' · '),
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            gapH(12),
            // Crew card row.
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.medical_services_rounded,
                      color: color, size: 22),
                ),
                gapW(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Unit ${unit?.callsign ?? '…'}',
                          style: const TextStyle(
                              color: AppColors.textInverse,
                              fontWeight: FontWeight.w600,
                              fontSize: 15)),
                      Text(
                        unit == null
                            ? 'Assigning crew'
                            : 'Crew of ${unit!.crewSize} · on duty',
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // Medical attached confirmation (spec §7, logged-in).
                if (state.isAuthenticated)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.14),
                      borderRadius:
                          BorderRadius.circular(AppColors.radiusFull),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded,
                            size: 12, color: AppColors.primary),
                        SizedBox(width: 4),
                        Text('Medical profile sent',
                            style: TextStyle(
                                color: AppColors.primary, fontSize: 10)),
                      ],
                    ),
                  ),
              ],
            ),
            gapH(12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    // Comms disabled offline (spec §7).
                    onPressed: offline
                        ? null
                        : () => showCommsSheet(context, state,
                            voiceFirst: true),
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      minimumSize: const Size.fromHeight(46),
                    ),
                    icon: const Icon(Icons.phone_rounded, size: 18),
                    label: const Text('Call crew'),
                  ),
                ),
                gapW(10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: offline
                        ? null
                        : () => showCommsSheet(context, state,
                            voiceFirst: false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textInverse,
                      side: const BorderSide(color: AppColors.borderDark),
                      minimumSize: const Size.fromHeight(46),
                    ),
                    icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                    label: const Text('Chat'),
                  ),
                ),
              ],
            ),
            if (offline)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  "You're offline. We'll reconnect automatically.",
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11),
                ),
              ),
            if (inc.status == MissionStatus.enRoute &&
                inc.etaSeconds > 120) ...[
              gapH(8),
              Text(
                'The crew is taking longer than expected. A dispatcher has been notified.',
                style: const TextStyle(
                    color: AppColors.statusPendingDark, fontSize: 11),
              ),
            ],
            if (!state.locationGranted) ...[
              gapH(8),
              Text(
                'Your location is off — the crew has your saved address.',
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 11),
              ),
            ],
            gapH(14),
            _TimelineStepper(inc: inc),
            gapH(14),
            // Persistent actions (spec §7).
            OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Dispatch hotline'),
                  content: const Text(
                      '150 · Emergency medical hotline\nYour location is shared on this call.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textInverse,
                side: const BorderSide(color: AppColors.borderDark),
                minimumSize: const Size.fromHeight(46),
              ),
              icon: const Icon(Icons.phone_rounded, size: 18),
              label: const Text('Call dispatcher'),
            ),
            gapH(4),
            TextButton(
              // Cancel disabled offline (spec §7).
              onPressed: offline ? null : () => _confirmCancel(context),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.danger),
              child: const Text('Cancel request'),
            ),
          ],
        ],
      ),
    );
  }

  void _confirmCancel(BuildContext context) => showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Cancel this request?'),
          content: const Text(
              "A crew has not been assigned yet. If you still need help, "
              "you'll have to send a new request."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Keep request'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                state.cancelRequest();
              },
              child: const Text('Cancel request'),
            ),
          ],
        ),
      );
}

/// Vertical 5-dot timeline stepper (spec §7): done / active / pending.
class _TimelineStepper extends StatelessWidget {
  final Incident inc;
  const _TimelineStepper({required this.inc});

  @override
  Widget build(BuildContext context) {
    const steps = [
      MissionStatus.dispatched,
      MissionStatus.enRoute,
      MissionStatus.onScene,
      MissionStatus.transporting,
      MissionStatus.atHospital,
    ];
    final reached = inc.status.index;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: steps[i].index <= reached
                        ? steps[i].light()
                        : AppColors.borderDark,
                    shape: BoxShape.circle,
                    border: steps[i].index == reached
                        ? Border.all(color: steps[i].light(), width: 3)
                        : null,
                  ),
                ),
                gapW(12),
                Text(
                  steps[i].label,
                  style: TextStyle(
                    color: steps[i].index <= reached
                        ? AppColors.textInverse
                        : AppColors.textMuted,
                    fontWeight: steps[i].index == reached
                        ? FontWeight.w700
                        : FontWeight.w400,
                    fontSize: 13,
                  ),
                ),
                if (steps[i].index == reached) ...[
                  gapW(8),
                  Text('now',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11)),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Comms sheet: voice-first with chat fallback (IA §3.8).
void showCommsSheet(BuildContext context, AppState state,
    {required bool voiceFirst}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetCtx) => Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(voiceFirst ? 'Talk to the crew' : 'Chat with the crew',
              style: Theme.of(sheetCtx).textTheme.headlineMedium),
          gapH(4),
          Text('Voice is fastest in an emergency. If a call fails, chat keeps working.',
              style: Theme.of(sheetCtx).textTheme.bodySmall),
          gapH(16),
          if (voiceFirst) ...[
            FilledButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(sheetCtx).showSnackBar(
                  const SnackBar(
                      content: Text(
                          "Call failed — the crew's line is busy. [Retry] / Open chat")),
                );
                Navigator.of(sheetCtx).pop();
                showCommsSheet(context, state, voiceFirst: false);
              },
              style:
                  FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.call_rounded),
              label: const Text('Call crew now'),
            ),
            gapH(8),
            TextButton.icon(
              onPressed: () {
                Navigator.of(sheetCtx).pop();
                showCommsSheet(context, state, voiceFirst: false);
              },
              icon: const Icon(Icons.chat_bubble_rounded, size: 18),
              label: const Text('Open chat instead'),
            ),
          ] else ...[
            const _MockChat(),
            gapH(12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Message the crew…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                gapW(8),
                IconButton.filled(
                  onPressed: () {},
                  icon: const Icon(Icons.send_rounded, size: 18),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

class _MockChat extends StatelessWidget {
  const _MockChat();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _bubble(theme, 'We received your request. ETA updated.', true),
        gapH(6),
        _bubble(theme, 'Please hurry.', false),
      ],
    );
  }

  Widget _bubble(ThemeData theme, String text, bool incoming) {
    return Align(
      alignment: incoming ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: incoming
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
        ),
        child: Text(text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: incoming ? null : AppColors.primaryForeground,
            )),
      ),
    );
  }
}

/// Round glass back button for the immersive mission view.
class _GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.panelDark.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: AppColors.textInverse, size: 22),
        ),
      ),
    );
  }
}
