import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/mission_status.dart';
import '../core/tokens.dart';
import '../theme/app_theme.dart';
import '../widgets/atoms.dart';
import 'mission_detail_screen.dart';

/// History (spec §11) — today's work at a glance + full audit trail.
///
/// Phone: list → push §12. Tablet: master–detail — 400dp list left, detail
/// in the right pane without navigation.
class HistoryScreen extends StatefulWidget {
  final AppState state;
  const HistoryScreen({super.key, required this.state});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  MissionHistoryEntry? _selected;

  AppState get state => widget.state;

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _duration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes % 60} min';
    }
    return '${d.inMinutes} min';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tablet = isTabletLayoutOf(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final list = _ListPane(
          state: state,
          tablet: tablet,
          selectedId: _selected?.id,
          onSelect: (e) => setState(() => _selected = e),
          hhmm: _hhmm,
          durationText: _duration,
        );
        if (!tablet) return list;
        return Row(
          children: [
            SizedBox(width: 400, child: list),
            Container(width: 1, color: theme.colorScheme.outlineVariant),
            Expanded(
              child: _selected == null
                  ? Center(
                      child: Text('Select a mission',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.outline)),
                    )
                  : MissionDetailScreen(state: state, entry: _selected!),
            ),
          ],
        );
      },
    );
  }
}

/// Tablet check without importing main.dart's helper into every file.
bool isTabletLayoutOf(BuildContext context) {
  final mq = MediaQuery.of(context);
  return mq.orientation == Orientation.landscape &&
      mq.size.shortestSide >= 600;
}

class _ListPane extends StatelessWidget {
  final AppState state;
  final bool tablet;
  final String? selectedId;
  final ValueChanged<MissionHistoryEntry> onSelect;
  final String Function(DateTime) hhmm;
  final String Function(Duration) durationText;
  const _ListPane({
    required this.state,
    required this.tablet,
    required this.selectedId,
    required this.onSelect,
    required this.hhmm,
    required this.durationText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (state.historyLoading) {
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        separatorBuilder: (_, _) => gapH(12),
        itemBuilder: (_, _) => const SkeletonBlock(height: 72),
      );
    }

    if (state.historyError) {
      return EmptyStateBox(
        icon: Icons.history_toggle_off_rounded,
        title: "Couldn't load history",
        message: 'Your completed missions are safe — retry when ready.',
        actionLabel: 'Retry',
        onAction: () => state.setHistoryError(false),
      );
    }

    final m = state.activeMission;
    return RefreshIndicator(
      onRefresh: () async {
        // Pull-to-refresh (spec §11); offline shows the cached stamp.
        await Future<void>.delayed(const Duration(milliseconds: 600));
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (state.offline) ...[
            Text('OFFLINE · Last updated ${hhmm(DateTime.now())}',
                style: theme.textTheme.labelSmall),
            gapH(12),
          ],
          // ── Active (pinned, colored left border = status) ────────────
          if (m != null) ...[
            Text('Active', style: theme.textTheme.labelLarge),
            gapH(8),
            _ActiveCard(
              state: state,
              mission: m,
              hhmm: hhmm,
            ),
            gapH(18),
          ],
          // ── Today ────────────────────────────────────────────────────
          Text('Today', style: theme.textTheme.labelLarge),
          gapH(8),
          if (state.history.isEmpty)
            EmptyStateBox(
              icon: Icons.route_outlined,
              title: 'No missions yet today',
              message: state.onDuty
                  ? 'Completed missions will appear here.'
                  : 'Go on duty to start receiving missions.',
            )
          else
            ...state.history.map(
              (e) => _HistoryRow(
                entry: e,
                selected: e.id == selectedId,
                compact: tablet,
                hhmm: hhmm,
                durationText: durationText,
                onTap: () {
                  if (tablet) {
                    onSelect(e);
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MissionDetailScreen(state: state, entry: e),
                      ),
                    );
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Pinned active mission — current phase + elapsed (spec §11).
class _ActiveCard extends StatelessWidget {
  final AppState state;
  final Mission mission;
  final String Function(DateTime) hhmm;
  const _ActiveCard({required this.state, required this.mission, required this.hhmm});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = context.statusColor(mission.status);
    final elapsed = DateTime.now().difference(mission.createdAt);
    final mm = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
      ),
      child: Row(
        children: [
          // Status-colored left accent (spec §11).
          Container(width: 4, height: 64, color: color),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(mission.status.stripLabel,
                            style: theme.textTheme.labelLarge
                                ?.copyWith(color: color)),
                        gapH(2),
                        Text(mission.pickupLabel,
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Text('$mm:$ss', style: etaDisplayStyle(size: 16)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final MissionHistoryEntry entry;
  final bool selected;
  final bool compact;
  final String Function(DateTime) hhmm;
  final String Function(Duration) durationText;
  final VoidCallback onTap;
  const _HistoryRow({
    required this.entry,
    required this.selected,
    required this.compact,
    required this.hhmm,
    required this.durationText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final green = context.statusColor(MissionStatus.resolved);
    return InkWell(
      borderRadius: BorderRadius.circular(AppColors.radiusMd),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.10)
              : theme.colorScheme.surface,
          border: Border.all(
              color: selected
                  ? AppColors.primary
                  : theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
        ),
        child: Row(
          children: [
            Text(hhmm(entry.endedAt), style: etaDisplayStyle(size: 13)),
            gapW(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.patientSummary, style: theme.textTheme.bodyMedium),
                  gapH(2),
                  Text(entry.route,
                      style: theme.textTheme.labelSmall, maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            gapW(8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppColors.radiusFull),
                  ),
                  child: Text('Completed',
                      style: theme.textTheme.labelSmall?.copyWith(color: green)),
                ),
                gapH(3),
                Text(durationText(entry.duration),
                    style: theme.textTheme.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
