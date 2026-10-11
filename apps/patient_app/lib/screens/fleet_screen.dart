import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_state.dart';
import '../core/mission_status.dart';
import '../core/tokens.dart';
import '../theme/app_theme.dart';
import '../widgets/atoms.dart';
import 'mission_screen.dart';
import 'request_flow.dart';
import 'settings_screen.dart';

/// Home tab: live fleet map + one-tap panic (screen spec §3).
///
/// States implemented: loading (tile/card skeletons) · empty ("call the
/// dispatcher instead") · error (Retry) · offline (flat bg, desaturated
/// hollow markers, panic still queues) · permission-denied ("Location off" chip).
/// Gestures: pan/zoom · drag sheet (¼ · ½ · ¾ snap) · pull-to-refresh sheet ·
/// tap marker → unit sheet (§4) · long-press map → set pickup pin (signed in).
class FleetScreen extends StatelessWidget {
  final AppState state;
  const FleetScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        final inc = state.activeIncident;
        final hasActive = inc != null && inc.status != MissionStatus.resolved;

        return LayoutBuilder(
          builder: (context, constraints) {
            final peek = constraints.maxHeight * 0.25; // sheet snap point ¼
            return Stack(
              children: [
                _FleetMap(
                  state: state,
                  dark: dark,
                  onUnitTap: (index) =>
                      showUnitDetailSheet(context, state, index),
                ),
                if (!state.locationGranted)
                  Positioned(
                    top: 0,
                    left: 16,
                    child: SafeArea(
                        bottom: false,
                        child: _LocationOffChip(state: state)),
                  ),
                if (hasActive)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _ActiveMissionSheet(state: state),
                  )
                else ...[
                  Positioned.fill(child: _FleetSheet(state: state)),
                  // Panic FAB floats above the sheet peek (spec §3).
                  Positioned(
                    right: 16,
                    bottom: peek + 16,
                    child: Semantics(
                      button: true,
                      label: 'Request help',
                      child: PanicButton(
                        onPressed: () => startRequestFlow(context, state),
                      ),
                    ),
                  ),
                ],
                if (!state.offline)
                  Positioned(
                    left: 4,
                    bottom: hasActive ? null : peek + 4,
                    top: hasActive ? 8 : null,
                    child: const SafeArea(
                      top: false,
                      child: MapAttribution(),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Panic entry shared by the FAB and the unit sheet (spec §3/§4/§5).
/// Opens the stacked-step request screen; nothing is sent until "Send request".
void startRequestFlow(BuildContext context, AppState state) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => RequestFlowScreen(state: state)),
  );
}

// ── Map ─────────────────────────────────────────────────────────────────

class _FleetMap extends StatelessWidget {
  final AppState state;
  final bool dark;
  final ValueChanged<int> onUnitTap;
  const _FleetMap({
    required this.state,
    required this.dark,
    required this.onUnitTap,
  });

  @override
  Widget build(BuildContext context) {
    final inc = state.activeIncident;
    final assigned = inc?.unitId == null
        ? null
        : state.units.where((u) => u.id == inc!.unitId).firstOrNull;
    final offline = state.offline;

    final markers = <Marker>[
      // My pin — hollow/muted while location is off (permission-denied state).
      Marker(
        point: state.userLocation,
        width: 18,
        height: 18,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: state.locationGranted
                ? AppColors.primary
                : Colors.transparent,
            border: Border.all(
              color: state.locationGranted
                  ? Colors.white
                  : AppColors.textMuted,
              width: 3,
            ),
            boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
          ),
        ),
      ),
      // Fleet units — desaturated + hollow ring when offline (spec §3).
      for (var i = 0; i < state.units.length; i++)
        Marker(
          point: state.units[i].position,
          width: 22,
          height: 22,
          child: GestureDetector(
            onTap: () => onUnitTap(i),
            child: Semantics(
              button: true,
              label: 'Ambulance ${state.units[i].callsign}',
              child: _UnitDot(
                unit: state.units[i],
                color: _unitColor(context, state.units[i], assigned, inc),
                offline: offline,
              ),
            ),
          ),
        ),
    ];

    return SizedBox.expand(
      child: ColoredBox(
        color: dark ? AppColors.backgroundDark : AppColors.background,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: state.userLocation,
            initialZoom: 13.5,
            backgroundColor:
                dark ? AppColors.backgroundDark : AppColors.background,
            onLongPress: (_, point) => _setPin(context, point),
          ),
          children: [
            if (!offline)
              TileLayer(
                urlTemplate: kOsmTileUrl,
                userAgentPackageName: 'com.ambulance.patient_app',
              ),
            MarkerLayer(markers: markers),
            if (assigned != null && inc != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [assigned.position, _routeTarget(inc)],
                    strokeWidth: 5,
                    color: context.statusColor(inc.status),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Color _unitColor(
      BuildContext context, AmbulanceUnit u, AmbulanceUnit? assigned, Incident? inc) {
    if (!u.available) {
      if (assigned != null && assigned.id == u.id && inc != null) {
        return context.statusColor(inc.status);
      }
      return AppColors.textMuted;
    }
    return context.statusColor(MissionStatus.resolved); // available → green
  }

  void _setPin(BuildContext context, LatLng point) {
    if (state.isAuthenticated) {
      state.setUserLocation(point);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pickup pin moved')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to move your pickup pin')),
      );
    }
  }

  LatLng _routeTarget(Incident inc) => switch (inc.status) {
        MissionStatus.transporting || MissionStatus.atHospital =>
          inc.hospital,
        _ => inc.pickup,
      };
}

class _UnitDot extends StatelessWidget {
  final AmbulanceUnit unit;
  final Color color;
  final bool offline;
  const _UnitDot({
    required this.unit,
    required this.color,
    this.offline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        // Offline: desaturated fill + hollow status ring (spec §3).
        color: offline ? color.withValues(alpha: 0.25) : color,
        shape: BoxShape.circle,
        border: Border.all(
          color: offline ? color : Colors.white,
          width: offline ? 3 : 2,
        ),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
      ),
      alignment: Alignment.center,
      child: unit.available || offline
          ? const SizedBox.shrink()
          : const Text('✚',
              style: TextStyle(color: Colors.white, fontSize: 10, height: 1)),
    );
  }
}

class _LocationOffChip extends StatelessWidget {
  final AppState state;
  const _LocationOffChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppColors.radiusFull),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          gapW(10),
          const Icon(Icons.location_off_rounded,
              size: 16, color: AppColors.statusPending),
          Text('Location off', style: theme.textTheme.labelLarge),
          TextButton(
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10)),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SettingsScreen(state: state)),
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

// ── Bottom sheet: unit list + states (spec §3) ─────────────────────────

class _FleetSheet extends StatelessWidget {
  final AppState state;
  const _FleetSheet({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.25,
      minChildSize: 0.18,
      maxChildSize: 0.75,
      snap: true,
      snapSizes: const [0.25, 0.5, 0.75],
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppColors.radiusLg)),
          boxShadow: const [
            BoxShadow(color: Color(0x290F172A), blurRadius: 16, offset: Offset(0, -4)),
          ],
        ),
        child: RefreshIndicator(
          onRefresh: () async => state.refreshFleet(),
          child: ListView(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(AppColors.radiusFull),
                  ),
                ),
              ),
              _header(context, theme),
              gapH(12),
              if (state.fleetLoading)
                _loadingCards(theme)
              else if (state.fleetError)
                _errorBlock(context, theme)
              else if (state.units.isEmpty)
                _emptyBlock(context, theme)
              else
                _unitCards(context),
              gapH(8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, ThemeData theme) {
    final available = state.units.where((u) => u.available).length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.fleetLoading
                    ? 'Looking for ambulances near you…'
                    : '${state.units.length} ambulances near you',
                style: theme.textTheme.headlineMedium,
              ),
              gapH(2),
              Text(
                state.fleetLoading
                    ? 'This takes a moment'
                    : 'Updated ${_agoLabel(state.lastFleetUpdate)}'
                        '${state.offline ? ' · last known positions' : ''}'
                        '${state.fleetError ? '' : ' · $available available'}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          onPressed: () => _showDispatcherDialog(context),
          icon: const Icon(Icons.phone_rounded, size: 16),
          label: const Text('Call dispatcher'),
        ),
      ],
    );
  }

  Widget _loadingCards(ThemeData theme) => SizedBox(
        height: 96,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: const [
            SkeletonBlock(width: 148, height: 96),
            SizedBox(width: 8),
            SkeletonBlock(width: 148, height: 96),
            SizedBox(width: 8),
            SkeletonBlock(width: 148, height: 96),
          ],
        ),
      );

  Widget _errorBlock(BuildContext context, ThemeData theme) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("We couldn't load the fleet.",
                style: theme.textTheme.bodyLarge),
            gapH(2),
            Text('Check your connection and try again.',
                style: theme.textTheme.bodySmall),
            gapH(12),
            FilledButton.tonalIcon(
              onPressed: state.refreshFleet,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      );

  Widget _emptyBlock(BuildContext context, ThemeData theme) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No ambulances available nearby.',
                style: theme.textTheme.bodyLarge),
            gapH(2),
            Text('Call the dispatcher instead — they can redirect a unit.',
                style: theme.textTheme.bodySmall),
            gapH(12),
            FilledButton.tonalIcon(
              onPressed: () => _showDispatcherDialog(context),
              icon: const Icon(Icons.phone_rounded, size: 18),
              label: const Text('Call dispatcher'),
            ),
          ],
        ),
      );

  Widget _unitCards(BuildContext context) => SizedBox(
        height: 96,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: state.units.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) => _UnitCard(
            unit: state.units[i],
            state: state,
            onTap: () => showUnitDetailSheet(context, state, i),
          ),
        ),
      );

  void _showDispatcherDialog(BuildContext context) => showDialog<void>(
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
      );
}

class _UnitCard extends StatelessWidget {
  final AmbulanceUnit unit;
  final AppState state;
  final VoidCallback onTap;
  const _UnitCard({
    required this.unit,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dist = _distanceMeters(state.userLocation, unit.position);
    final assigned = state.activeIncident?.unitId == unit.id;
    final statusText = !unit.available
        ? (assigned ? state.activeIncident!.status.label : 'Unavailable')
        : 'Available now';
    return SizedBox(
      width: 148,
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: theme.colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(unit.callsign,
                        style: etaDisplayStyle(size: 15)),
                    const Spacer(),
                    Text(_distLabel(dist),
                        style: theme.textTheme.labelSmall),
                  ],
                ),
                gapH(4),
                Text('${unit.vehicleType} · crew of ${unit.crewSize}',
                    style: theme.textTheme.labelSmall),
                const Spacer(),
                Text(
                  statusText,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: unit.available
                        ? context.statusColor(MissionStatus.resolved)
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Unit detail sheet (spec §4): swipe horizontally → next unit ────────

Future<void> showUnitDetailSheet(
  BuildContext context,
  AppState state,
  int initialIndex, {
  VoidCallback? onRequestHelp,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _UnitDetailPager(
        state: state,
        initialIndex: initialIndex.clamp(0, state.units.length - 1),
        // Uses the caller's context (still mounted under the sheet route),
        // never the sheet's own, which is unmounted after pop.
        onRequestHelp: onRequestHelp ?? () => startRequestFlow(context, state),
      ),
    );

class _UnitDetailPager extends StatefulWidget {
  final AppState state;
  final int initialIndex;
  final VoidCallback onRequestHelp;
  const _UnitDetailPager({
    required this.state,
    required this.initialIndex,
    required this.onRequestHelp,
  });

  @override
  State<_UnitDetailPager> createState() => _UnitDetailPagerState();
}

class _UnitDetailPagerState extends State<_UnitDetailPager> {
  late final PageController _pages =
      PageController(initialPage: widget.initialIndex);
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('Nearby units', style: theme.textTheme.labelLarge),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          SizedBox(
            height: 300,
            child: PageView.builder(
              controller: _pages,
              itemCount: widget.state.units.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => _UnitDetailPage(
                unit: widget.state.units[i],
                state: widget.state,
                onRequestHelp: () {
                  Navigator.of(context).pop(); // close the unit sheet first
                  widget.onRequestHelp();
                },
              ),
            ),
          ),
          gapH(8),
          // Swipe hint: dot per unit.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.state.units.length; i++)
                Container(
                  width: i == _index ? 16 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == _index
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    borderRadius:
                        BorderRadius.circular(AppColors.radiusFull),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UnitDetailPage extends StatelessWidget {
  final AmbulanceUnit unit;
  final AppState state;
  final VoidCallback onRequestHelp;
  const _UnitDetailPage({
    required this.unit,
    required this.state,
    required this.onRequestHelp,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dist = _distanceMeters(state.userLocation, unit.position);
    final assignedIncident = state.activeIncident?.unitId == unit.id
        ? state.activeIncident
        : null;
    final available = unit.available;
    final statusColor = available
        ? context.statusColor(MissionStatus.resolved)
        : assignedIncident != null
            ? context.statusColor(assignedIncident.status)
            : theme.colorScheme.outline;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(AppColors.radiusMd),
                ),
                child: const Icon(Icons.local_hospital_rounded,
                    color: Colors.white, size: 26),
              ),
              gapW(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Unit ${unit.callsign}',
                        style: theme.textTheme.headlineMedium),
                    Text(
                      available
                          ? 'Available now'
                          : assignedIncident != null
                              ? '${assignedIncident.status.label} · another mission'
                              : 'Unavailable',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: statusColor),
                    ),
                  ],
                ),
              ),
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(unit.vehicleType,
                    style: theme.textTheme.labelSmall),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ],
          ),
          gapH(16),
          Row(
            children: [
              _StatBox(
                label: 'Distance',
                value: _distLabel(dist),
              ),
              gapW(8),
              _StatBox(
                label: 'ETA',
                value: '≈ ${_etaMinutes(dist)} min',
              ),
              gapW(8),
              _StatBox(
                label: 'Crew',
                value: '${unit.crewSize}',
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppColors.radiusLg)),
              ),
              onPressed: available ? onRequestHelp : null,
              icon: const Icon(Icons.emergency_rounded),
              label: Text(
                state.isAuthenticated ? 'Request this unit' : 'Request help',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          ),
          gapH(8),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
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
              icon: const Icon(Icons.phone_rounded, size: 18),
              label: const Text('Call dispatcher'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelSmall),
            gapH(2),
            Text(value, style: etaDisplayStyle(size: 16)),
          ],
        ),
      ),
    );
  }
}

// ── Map helpers ─────────────────────────────────────────────────────────

const Distance _geo = Distance();

double _distanceMeters(LatLng a, LatLng b) =>
    _geo.as(LengthUnit.Meter, a, b);

String _distLabel(double meters) => meters < 1000
    ? '${meters.round()} m'
    : '${(meters / 1000).toStringAsFixed(1)} km';

/// Demo average city speed ≈ 30 km/h (500 m/min).
int _etaMinutes(double meters) => (meters / 500).ceil().clamp(1, 99);

String _agoLabel(DateTime t) {
  final s = DateTime.now().difference(t).inSeconds;
  if (s < 10) return 'just now';
  if (s < 60) return '$s s ago';
  return '${s ~/ 60} min ago';
}

// ── Active-mission strip (Mission-Critical theming, hybrid lock) ───────

class _ActiveMissionSheet extends StatelessWidget {
  final AppState state;
  const _ActiveMissionSheet({required this.state});

  @override
  Widget build(BuildContext context) {
    final inc = state.activeIncident!;
    final theme = Theme.of(context);
    final color = context.statusColor(inc.status);
    final dark = theme.brightness == Brightness.dark;
    final bg = dark ? AppColors.panelDark : AppColors.surface;
    final unit = inc.unitId == null
        ? null
        : state.units.where((u) => u.id == inc.unitId).firstOrNull;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MissionScreen(state: state)),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          decoration: BoxDecoration(
            color: bg,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(AppColors.radiusLg)),
            boxShadow: const [BoxShadow(color: Color(0x40111C2E), blurRadius: 18)],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                        width: 4,
                        height: 44,
                        decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(2))),
                    gapW(12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${inc.status.label.toUpperCase()} — Unit ${unit?.callsign ?? '…'}',
                            style: theme.textTheme.labelLarge,
                          ),
                          if (unit != null)
                            Text('Crew of ${unit.crewSize}',
                                style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    StatusChip(status: inc.status),
                  ],
                ),
                gapH(12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Arriving at your location',
                        style: theme.textTheme.bodyMedium),
                    MonoEta(
                      elapsed: inc.etaSeconds > 0
                          ? Duration(seconds: inc.etaSeconds)
                          : null,
                      size: AppText.h2Size + 6,
                      color: color,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Map attribution (OSM tile policy).
class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(4),
        child: Text('© OpenStreetMap contributors',
            style: Theme.of(context).textTheme.labelSmall),
      );
}

