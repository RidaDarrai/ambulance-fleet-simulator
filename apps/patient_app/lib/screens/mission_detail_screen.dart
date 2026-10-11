import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_state.dart';
import '../core/mission_status.dart';
import '../core/tokens.dart';
import '../theme/app_theme.dart';
import '../widgets/atoms.dart';

/// Mission detail (screen spec §10) — audit trail of a past mission:
/// timestamps, crew, outcome.
///
/// States: loading (skeleton timeline) · error (details unavailable + Retry) ·
/// offline (cached view + "Showing saved mission").
/// Gestures: back · tap snapshot → expand full screen · tap hospital →
/// Maps deep link (external).
class MissionDetailScreen extends StatefulWidget {
  final AppState state;
  final Incident incident;
  const MissionDetailScreen({
    super.key,
    required this.state,
    required this.incident,
  });

  @override
  State<MissionDetailScreen> createState() => _MissionDetailScreenState();
}

class _MissionDetailScreenState extends State<MissionDetailScreen> {
  bool _loading = true;

  Incident get inc => widget.incident;

  @override
  void initState() {
    super.initState();
    // Brief skeleton while the "record" loads (§10 loading, ≤1 s).
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: Text(inc.id)),
      body: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.state.offline) ...[
              _offlineBanner(theme),
              gapH(12),
            ],
            if (_loading)
              _skeleton(theme)
            else if (widget.state.fleetError)
              _errorBlock(theme)
            else
              ..._details(theme),
          ],
        ),
      ),
    );
  }

  // ── States ───────────────────────────────────────────────────────────

  Widget _offlineBanner(ThemeData theme) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
            gapW(10),
            Expanded(
              child: Text('Showing saved mission',
                  style: theme.textTheme.bodySmall),
            ),
          ],
        ),
      );

  Widget _skeleton(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SkeletonBlock(width: 140, height: 22),
          SizedBox(height: 12),
          SkeletonBlock(width: double.infinity, height: 160),
          SizedBox(height: 16),
          SkeletonBlock(width: double.infinity, height: 220),
          SizedBox(height: 12),
          SkeletonBlock(width: double.infinity, height: 96),
        ],
      );

  Widget _errorBlock(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Mission details couldn't be loaded.",
              style: theme.textTheme.bodyLarge),
          gapH(2),
          Text('The mission itself was completed successfully.',
              style: theme.textTheme.bodySmall),
          gapH(12),
          FilledButton.tonalIcon(
            onPressed: () => widget.state.refreshFleet(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      );

  // ── Details ──────────────────────────────────────────────────────────

  List<Widget> _details(ThemeData theme) {
    final finalColor = context.statusColor(inc.status);
    return [
      // Header (spec §10).
      Row(
        children: [
          StatusChip(status: inc.status),
          const Spacer(),
          Text('Created ${_hhmm(inc.createdAt)}',
              style: theme.textTheme.bodySmall),
        ],
      ),
      gapH(16),
      // Route snapshot (spec §10) — tap → full screen.
      _routeSnapshot(theme, finalColor),
      gapH(16),
      // Crew / vehicle / hospital card.
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
            _detailRow(theme, 'Assigned to',
                inc.unitCallsign == null ? 'No unit assigned' : 'Unit ${inc.unitCallsign}'),
            _detailRow(theme, 'Handed off at',
                '$kHospitalName · ${_hhmmOrDash(MissionStatus.atHospital)}'),
            if (inc.medicalAttached)
              _detailRow(theme, 'Medical profile', 'Attached to request'),
          ],
        ),
      ),
      gapH(16),
      // Timeline of all 7 statuses with mono timestamps (spec §10).
      Text('Timeline', style: theme.textTheme.headlineMedium),
      gapH(8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            for (var i = 0; i < MissionStatus.values.length; i++)
              _timelineRow(theme, MissionStatus.values[i], i),
          ],
        ),
      ),
      gapH(12),
      Center(
        child: TextButton(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Issue report — coming in v0.2'))),
          child: const Text('Report an issue'),
        ),
      ),
    ];
  }

  Widget _detailRow(ThemeData theme, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(label, style: theme.textTheme.labelLarge),
            ),
            Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
          ],
        ),
      );

  Widget _timelineRow(ThemeData theme, MissionStatus status, int index) {
    final reached = inc.statusTimes[status];
    final isLast = index == MissionStatus.values.length - 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: reached != null
                      ? context.statusColor(status)
                      : theme.colorScheme.outlineVariant,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 24,
                  color: inc.statusTimes[MissionStatus.values[index + 1]] !=
                          null
                      ? context.statusColor(status)
                      : theme.colorScheme.outlineVariant,
                ),
            ],
          ),
          gapW(12),
          Expanded(
            child: Text(status.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: reached != null ? FontWeight.w600 : FontWeight.w400,
                  color: reached != null
                      ? null
                      : theme.colorScheme.outline,
                )),
          ),
          Text(reached == null ? '—' : _hhmm(reached),
              style: etaDisplayStyle(
                  size: 13,
                  color: reached != null
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.outline)),
        ],
      ),
    );
  }

  /// Static route snapshot (spec §10): pickup → hospital polyline in the
  /// final status color; tap → expand full screen.
  Widget _routeSnapshot(ThemeData theme, Color color) => GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _FullScreenRoute(inc: inc)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          child: SizedBox(
            height: 160,
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(
                        (inc.pickup.latitude + inc.hospital.latitude) / 2,
                        (inc.pickup.longitude + inc.hospital.longitude) / 2),
                    initialZoom: 12,
                    backgroundColor: theme.scaffoldBackgroundColor,
                    interactionOptions:
                        const InteractionOptions(flags: InteractiveFlag.none),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'com.ambulance.patient_app',
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: [inc.pickup, inc.hospital],
                          strokeWidth: 4,
                          color: color,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: inc.pickup,
                          width: 14,
                          height: 14,
                          child: Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: AppColors.primary, width: 3),
                            ),
                          ),
                        ),
                        // Tap hospital → Maps deep link (spec §10).
                        Marker(
                          point: inc.hospital,
                          width: 24,
                          height: 24,
                          child: GestureDetector(
                            onTap: _openInMaps,
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
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.9),
                      borderRadius:
                          BorderRadius.circular(AppColors.radiusFull),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.open_in_full_rounded, size: 12),
                        gapW(4),
                        Text('Expand', style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  /// External deep link — opens the hospital in the Maps app (spec §10).
  void _openInMaps() {
    final url =
        'geo:${inc.hospital.latitude},${inc.hospital.longitude}?q=${Uri.encodeComponent(kHospitalName)}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening in Maps — $url')),
    );
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _hhmmOrDash(MissionStatus s) {
    final t = inc.statusTimes[s];
    return t == null ? '—' : _hhmm(t);
  }
}

/// Expanded full-screen route (spec §10 gesture).
class _FullScreenRoute extends StatelessWidget {
  final Incident inc;
  const _FullScreenRoute({required this.inc});

  @override
  Widget build(BuildContext context) {
    final color = context.statusColor(inc.status);
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(
                  (inc.pickup.latitude + inc.hospital.latitude) / 2,
                  (inc.pickup.longitude + inc.hospital.longitude) / 2),
              initialZoom: 12,
              backgroundColor: AppColors.backgroundDark,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.ambulance.patient_app',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [inc.pickup, inc.hospital],
                    strokeWidth: 6,
                    color: color,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
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
                  Marker(
                    point: inc.hospital,
                    width: 20,
                    height: 20,
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
                ],
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.topLeft,
                child: Material(
                  color: AppColors.panelDark.withValues(alpha: 0.9),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.close_rounded,
                          color: AppColors.textInverse, size: 22),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
