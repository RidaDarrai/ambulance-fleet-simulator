import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../core/app_state.dart';
import '../core/mission_status.dart';
import '../core/tokens.dart';
import '../theme/app_theme.dart';
import '../widgets/atoms.dart';

/// Mission detail (spec §12) — the after-action record, same audit language
/// as the patient app. Push on phone, right pane on tablet (master–detail).
class MissionDetailScreen extends StatelessWidget {
  final AppState state;
  final MissionHistoryEntry entry;
  const MissionDetailScreen(
      {super.key, required this.state, required this.entry});

  static const _phases = MissionStatus.values; // 7 dots

  String _ts(DateTime? t) => t == null
      ? '—'
      : '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}:'
          '${t.second.toString().padLeft(2, '0')}';

  String _dur(Duration? d) => d == null
      ? '—'
      : d.inMinutes > 0
          ? '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}'
          : '0:${d.inSeconds.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = entry;
    final green = context.statusColor(MissionStatus.resolved);
    final messages = state.messages(e.id);
    return Scaffold(
      // Phone push gets its own app bar; the tablet pane renders inline.
      appBar: isTabletOf(context)
          ? null
          : AppBar(title: Text(e.id, style: etaDisplayStyle(size: 16))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Header: status chip + id ───────────────────────────────
          Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 18, color: green),
              gapW(8),
              Text('Completed', style: theme.textTheme.labelLarge
                  ?.copyWith(color: green)),
              const Spacer(),
              Text(e.id, style: etaDisplayStyle(size: 13)),
            ],
          ),
          gapH(16),

          // ── Patient + hospital rows ───────────────────────────────
          _Row(
            icon: e.isGuest
                ? Icons.person_off_outlined
                : Icons.medical_information_outlined,
            label: 'Patient',
            value: e.isGuest
                ? 'Guest caller · no profile'
                : '${e.bloodType ?? '—'} patient',
          ),
          gapH(10),
          _Row(
            icon: Icons.local_hospital_outlined,
            label: 'Hospital',
            value: e.hospital ?? '—',
          ),
          gapH(10),
          _Row(
            icon: Icons.route_outlined,
            label: 'Route',
            value: e.route,
          ),
          gapH(20),

          // ── 7-dot timeline with mono timestamps ───────────────────
          Text('Timeline', style: theme.textTheme.labelLarge),
          gapH(10),
          ...List.generate(_phases.length, (i) {
            final phase = _phases[i];
            final at = e.timeline?[phase];
            final last = i == _phases.length - 1;
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: at != null
                              ? context.statusColor(phase)
                              : Colors.transparent,
                          border: at == null
                              ? Border.all(color: theme.colorScheme.outline)
                              : null,
                        ),
                      ),
                      if (!last)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: e.timeline?[_phases[i + 1]] != null
                                ? context.statusColor(_phases[i + 1])
                                    .withValues(alpha: 0.4)
                                : theme.colorScheme.outlineVariant,
                          ),
                        ),
                    ],
                  ),
                  gapW(12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(phase.stripLabel,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(
                                        color: at == null
                                            ? theme.colorScheme.outline
                                            : null)),
                          ),
                          Text(_ts(at),
                              style: etaDisplayStyle(
                                  size: 13,
                                  color: at == null
                                      ? theme.colorScheme.outline
                                      : theme.colorScheme.onSurface)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          gapH(8),

          // ── Durations block ────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _DurationCard(
                    label: 'Response', value: _dur(e.response)),
              ),
              gapW(10),
              Expanded(
                child: _DurationCard(
                    label: 'Transport', value: _dur(e.transport)),
              ),
              gapW(10),
              Expanded(
                child: _DurationCard(
                    label: 'Total', value: _dur(e.duration)),
              ),
            ],
          ),
          gapH(20),

          // ── Route snapshot (tap → fullscreen map) ──────────────────
          Text('Route snapshot', style: theme.textTheme.labelLarge),
          gapH(10),
          InkWell(
            borderRadius: BorderRadius.circular(AppColors.radiusMd),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => _FullScreenMap(state: state, entry: e),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppColors.radiusMd),
              child: SizedBox(
                height: 140,
                child: IgnorePointer(child: _RouteMap(state: state, entry: e)),
              ),
            ),
          ),
          gapH(20),

          // ── Chat transcript ────────────────────────────────────────
          Text('Chat transcript', style: theme.textTheme.labelLarge),
          gapH(10),
          if (messages.isEmpty)
            Text('No messages were exchanged.',
                style: theme.textTheme.bodySmall)
          else
            ...messages.map(
              (msg) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      msg.senderRole == 'crew'
                          ? Icons.local_hospital_outlined
                          : msg.senderRole == 'patient'
                              ? Icons.person_outline_rounded
                              : Icons.support_agent_outlined,
                      size: 16,
                      color: theme.colorScheme.outline,
                    ),
                    gapW(8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(msg.text, style: theme.textTheme.bodySmall),
                          Text(
                            '${msg.senderRole} · ${_ts(msg.at)}',
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          gapH(16),

          // ── Report an issue (prefilled id) ─────────────────────────
          OutlinedButton.icon(
            onPressed: () => _reportSheet(context),
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: const Text('Report an issue'),
          ),
          gapH(24),
        ],
      ),
    );
  }

  void _reportSheet(BuildContext context) {
    final reasons = ['Wrong address', 'Equipment', 'Other'];
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
                Text('Report an issue', style: theme.textTheme.headlineSmall),
                gapH(4),
                Text('Mission ${entry.id}', style: etaDisplayStyle(size: 13)),
                gapH(14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: reasons
                      .map((r) => ActionChip(
                            label: Text(r),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Issue reported to dispatch — $r')),
                              );
                            },
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

bool isTabletOf(BuildContext context) {
  final mq = MediaQuery.of(context);
  return mq.orientation == Orientation.landscape &&
      mq.size.shortestSide >= 600;
}

// ── Small parts ────────────────────────────────────────────────────────

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _Row({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.outline),
        gapW(10),
        Text(label, style: theme.textTheme.labelSmall),
        gapW(10),
        Expanded(
          child: Text(value,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.right),
        ),
      ],
    );
  }
}

class _DurationCard extends StatelessWidget {
  final String label;
  final String value;
  const _DurationCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
      ),
      child: Column(
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          gapH(4),
          Text(value, style: etaDisplayStyle(size: 18)),
        ],
      ),
    );
  }
}

// ── Route map (snapshot + fullscreen) ──────────────────────────────────

class _RouteMap extends StatelessWidget {
  final AppState state;
  final MissionHistoryEntry entry;
  const _RouteMap({required this.state, required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Demo approximation: the real app stores the mission's polyline
    // server-side (FirebaseRepository pass). Markers show the unit base and
    // the configured hospitals.
    return FlutterMap(
      options: MapOptions(
        initialCenter: state.unitPosition,
        initialZoom: 12,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.ambulance.crew_app',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: state.unitPosition,
              width: 24,
              height: 24,
              child: Icon(Icons.local_hospital_rounded,
                  size: 18, color: theme.colorScheme.primary),
            ),
            ...state.hospitals.map(
              (h) => Marker(
                point: h.location,
                width: 24,
                height: 24,
                child: Icon(Icons.local_hospital_outlined,
                    size: 18, color: theme.colorScheme.outline),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FullScreenMap extends StatelessWidget {
  final AppState state;
  final MissionHistoryEntry entry;
  const _FullScreenMap({required this.state, required this.entry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Route · ${entry.id}', style: etaDisplayStyle(size: 16))),
      body: _RouteMap(state: state, entry: entry),
    );
  }
}
