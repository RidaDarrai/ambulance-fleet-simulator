import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/mission_status.dart';
import '../core/tokens.dart';
import '../widgets/atoms.dart';
import 'mission_detail_screen.dart';
import 'mission_screen.dart';

/// Missions tab (screen spec §9).
///
/// * Active mission pinned at the top (2px left border in the status color,
///   live ETA chip in mono)
/// * Segmented control **Active | History** below
/// * History rows: status chip + incident ID (mono) + relative time; tapping a
///   row opens its full timestamp in a detail sheet
class MissionsScreen extends StatefulWidget {
  final AppState state;
  final VoidCallback onGoToMap;

  const MissionsScreen({
    super.key,
    required this.state,
    required this.onGoToMap,
  });

  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen> {
  /// 0 = Active, 1 = History. Auto-selects Active whenever a mission is live
  /// and History when idle — unless the user explicitly picks a segment, which
  /// then sticks for the rest of the session. (Previously the segment was set
  /// only in initState, so a mission that activated *after* the first build
  /// left the tab stuck on the empty History view.)
  int _segment = 1;
  bool _userChoseSegment = false;

  AppState get state => widget.state;

  bool get _hasActive =>
      state.activeIncident != null &&
      state.activeIncident!.status != MissionStatus.resolved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Missions')),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final active = _hasActive ? state.activeIncident : null;
          // Follow the live mission unless the user has chosen a segment.
          final segment =
              _userChoseSegment ? _segment : (active != null ? 0 : 1);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (active != null) ...[
                _ActiveCard(
                  inc: active,
                  state: state,
                  compact: true,
                ),
                gapH(16),
              ],
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Active')),
                  ButtonSegment(value: 1, label: Text('History')),
                ],
                selected: {segment},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() {
                  _userChoseSegment = true;
                  _segment = s.first;
                }),
              ),
              gapH(16),
              if (segment == 0)
                active == null
                  ? EmptyStateBox(
                      icon: Icons.navigation_outlined,
                      title: 'No active mission',
                      message: 'When you send a request, its live status and '
                          'ETA appear here until the crew reaches you.',
                      actionLabel: 'Open the map',
                      onAction: widget.onGoToMap,
                    )
                  : _ActiveCard(inc: active, state: state)
              else
                state.history.isEmpty
                    ? EmptyStateBox(
                        icon: Icons.history_rounded,
                        title: 'No missions yet',
                        message: 'Requests you send will appear here with '
                            'their status and crew details.',
                        actionLabel: 'Back to map',
                        onAction: widget.onGoToMap,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('History',
                              style: theme.textTheme.headlineMedium),
                          gapH(8),
                          for (final inc in state.history) ...[
                            _HistoryCard(inc: inc, state: state),
                            gapH(8),
                          ],
                        ],
                      ),
            ],
          );
        },
      ),
    );
  }
}

class _ActiveCard extends StatelessWidget {
  final Incident inc;
  final AppState state;

  /// Pinned-row variant: status chip + ID + live ETA only.
  final bool compact;

  const _ActiveCard({required this.inc, required this.state, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = context.statusColor(inc.status);
    final etaAvailable = inc.etaSeconds > 0;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          left: BorderSide(color: color, width: 2),
          top: BorderSide(color: theme.colorScheme.outlineVariant),
          right: BorderSide(color: theme.colorScheme.outlineVariant),
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        borderRadius: BorderRadius.circular(AppColors.radiusLg),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusChip(status: inc.status),
                const Spacer(),
                MonoEta(
                  elapsed: etaAvailable ? Duration(seconds: inc.etaSeconds) : null,
                  size: 18,
                  color: etaAvailable ? color : theme.colorScheme.outline,
                ),
              ],
            ),
            gapH(8),
            Text(
              '${inc.id} · queue #${inc.queuePosition}',
              style: theme.textTheme.bodySmall,
            ),
            if (!compact) ...[
              gapH(4),
              Text(
                'Pinned pickup: ${inc.pickup.latitude.toStringAsFixed(4)}, '
                '${inc.pickup.longitude.toStringAsFixed(4)}',
                style: theme.textTheme.labelSmall,
              ),
            ],
            gapH(12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(foregroundColor: color),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => MissionScreen(state: state)),
                ),
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text('Track mission'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final Incident inc;
  final AppState state;
  const _HistoryCard({required this.inc, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
        ),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.statusResolved.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child:
              const Icon(Icons.check_rounded, color: AppColors.statusResolved),
        ),
        title: Text(inc.id, style: theme.textTheme.bodyMedium),
        subtitle: Text('Resolved · ${timeAgo(inc.createdAt)}',
            style: theme.textTheme.labelSmall),
        trailing: StatusChip(status: inc.status),
        // Tap a row → full audit trail (screen spec §10).
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => MissionDetailScreen(state: state, incident: inc)),
        ),
      ),
    );
  }
}

String timeAgo(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}
