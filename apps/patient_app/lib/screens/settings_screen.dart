import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/mission_status.dart';
import '../core/tokens.dart';
import '../theme/app_theme.dart';
import '../widgets/atoms.dart';

/// Settings — pushed from Profile (approved 3-tab shell: Map · Missions ·
/// Profile). Groups follow the IA: **Notifications (§15)** · **Privacy &
/// permissions (§16)** · **Appearance (§16)** · **Accessibility** ·
/// **About (§16)** · demo toggles for reviewing states.
class SettingsScreen extends StatelessWidget {
  final AppState state;
  const SettingsScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── §15 Notifications ─────────────────────────────────────
            _section(context, 'Notifications'),
            if (state.notificationsDenied) ...[
              _deniedBanner(context, theme),
              gapH(8),
            ],
            if (state.notificationsPendingSync) ...[
              _pendingChipRow(context, theme),
              gapH(4),
            ],
            // Mission updates: locked ON while a mission is active.
            SwitchListTile(
              title: const Text('Mission updates'),
              subtitle: Text(state.activeIncident != null &&
                      state.activeIncident!.status != MissionStatus.resolved
                  ? "Required so you know when a crew is assigned — can't be "
                      'turned off during an active request'
                  : 'Required so you know when a crew is assigned'),
              value: state.missionAlerts,
              onChanged: state.notificationsDenied
                  ? null
                  : (v) => _guarded(
                        context,
                        () => state.setMissionAlerts(
                          v,
                          missionActive: state.activeIncident != null,
                        ),
                      ),
            ),
            SwitchListTile(
              title: const Text('Crew messages'),
              subtitle: const Text('Chat and call alerts from your crew'),
              value: state.crewMessages,
              onChanged: state.notificationsDenied
                  ? null
                  : (v) =>
                      _guarded(context, () => state.setCrewMessages(v)),
            ),
            SwitchListTile(
              title: const Text('Arrival alerts'),
              subtitle: const Text('Know the moment the crew reaches you'),
              value: state.arrivalAlerts,
              onChanged: state.notificationsDenied
                  ? null
                  : (v) =>
                      _guarded(context, () => state.setArrivalAlerts(v)),
            ),
            SwitchListTile(
              title: const Text('Tips & product news'),
              subtitle:
                  const Text("We'll never send marketing without your opt-in."),
              value: state.tipsNews,
              onChanged: state.notificationsDenied
                  ? null
                  : (v) => _guarded(context, () => state.setTipsNews(v)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Quiet hours'),
              subtitle: const Text(
                  'Respect your system Focus / Do Not Disturb by default'),
              trailing: Switch(
                value: state.quietHoursRespectOs,
                onChanged: state.notificationsDenied
                    ? null
                    : (v) => state.setQuietHours(v),
              ),
            ),
            if (state.notificationsDenied)
              OutlinedButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Opening system Settings…'))),
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text('Open Settings'),
              ),
            gapH(4),
            Text(
              'Badges always reflect unresolved missions, even if alerts are '
              'muted.',
              style: theme.textTheme.labelSmall,
            ),

            // ── §16 Privacy & permissions ─────────────────────────────
            _section(context, 'Privacy & permissions'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.my_location_outlined, size: 22),
              title: const Text('Location'),
              subtitle: const Text('While using the app'),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (state.locationGranted
                          ? AppColors.statusResolved
                          : AppColors.statusPending)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppColors.radiusFull),
                ),
                child: Text(
                  state.locationGranted ? 'Allowed' : 'Denied',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: state.locationGranted
                          ? AppColors.statusResolved
                          : AppColors.statusPending),
                ),
              ),
            ),
            if (!state.locationGranted)
              Padding(
                padding: const EdgeInsets.only(left: 56, bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero),
                    onPressed: () => state.setLocationGranted(true),
                    child: const Text('Open Settings'),
                  ),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Share anonymous analytics'),
              subtitle: const Text('Off by default — help us improve'),
              value: state.analyticsOptIn,
              onChanged: state.setAnalyticsOptIn,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.download_rounded, size: 22),
              title: const Text('Download your data'),
              subtitle: Text(state.offline
                  ? "Export will start when you're back online."
                  : 'JSON export of your profile and missions'),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.offline
                      ? "Export will start when you're back online."
                      : 'Export started — check your downloads.'),
                ),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_outline_rounded, size: 22),
              title: Text('Delete account and all data',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: AppColors.danger)),
              onTap: () => _confirmDelete(context),
            ),
            gapH(4),
            Text(
              'Your medical profile is encrypted and shared only with the '
              'crew assigned to your request.',
              style: theme.textTheme.labelSmall,
            ),
            _linkTile(context, 'Privacy policy'),

            // ── §16 Appearance ────────────────────────────────────────
            _section(context, 'Appearance'),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ],
              selected: {state.themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (s) =>
                  state.setThemeMode(s.first),
            ),
            gapH(6),
            Text(
              'Mission screens always use the mission theme — dark while a '
              'crew is on the way, calm at rest.',
              style: theme.textTheme.labelSmall,
            ),

            // ── Accessibility ─────────────────────────────────────────
            _section(context, 'Accessibility'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reduce motion'),
              subtitle: const Text('Disables the SOS pulse ring and shimmer'),
              value: state.reduceMotion,
              onChanged: state.setReduceMotion,
            ),

            // ── §16 About ─────────────────────────────────────────────
            _section(context, 'About'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.info_outline_rounded, size: 22),
              title: const Text('Ambulance Tracker — Patient app'),
              trailing: Text('v0.1',
                  style: etaDisplayStyle(size: 13)),
            ),
            _linkTile(context, 'Open-source licenses'),
            _linkTile(context, 'Terms of service'),
            _linkTile(context, 'Help & FAQ'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading:
                  const Icon(Icons.replay_rounded, size: 22),
              title: const Text('Replay onboarding'),
              onTap: () {
                state.completeOnboarding();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Onboarding will replay on next launch')));
              },
            ),

            // ── Demo toggles (state review) ───────────────────────────
            _section(context, 'State (demo)'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Simulate offline'),
              subtitle: const Text('SOS queues requests until reconnection.'),
              value: state.offline,
              onChanged: state.setOffline,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Simulate fleet error'),
              subtitle: const Text('Map sheet shows error + Retry.'),
              value: state.fleetError,
              onChanged: state.setFleetError,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Simulate send failure'),
              subtitle:
                  const Text('SOS write is rejected — error state (§6).'),
              value: state.simulateSubmitError,
              onChanged: state.setSimulateSubmitError,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Simulate save failure'),
              subtitle:
                  const Text('Medical profile edits fail — form kept (§11).'),
              value: state.simulateSaveError,
              onChanged: state.setSimulateSaveError,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Simulate notification save error'),
              subtitle:
                  const Text('Toggle reverts + snackbar (spec §15).'),
              value: state.simulateNotifSaveError,
              onChanged: (v) => state.simulateNotifSaveError = v,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Notifications denied (OS)'),
              subtitle:
                  const Text('Banner + Open Settings (spec §15).'),
              value: state.notificationsDenied,
              onChanged: state.setNotificationsDenied,
            ),
            gapH(24),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  /// §15 error: the change is rejected → caller reverts + snackbar.
  void _guarded(BuildContext context, bool Function() apply) {
    if (!apply()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Mission updates can't be turned off while you "
              'have an active request.')));
      return;
    }
    if (state.simulateNotifSaveError) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't save that change. Try again.")));
    }
  }

  void _confirmDelete(BuildContext context) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete your account?'),
          content: const Text(
              'This permanently removes your profile, medical info and '
              "mission history. This can't be undone."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: () {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Account deletion — demo only')));
              },
              child: const Text('Delete'),
            ),
          ],
        ),
      );

  Widget _deniedBanner(BuildContext context, ThemeData theme) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.statusColor(MissionStatus.pending)
              .withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
        ),
        child: Row(
          children: [
            Icon(Icons.notifications_off_outlined,
                size: 18, color: context.statusColor(MissionStatus.pending)),
            gapW(10),
            Expanded(
              child: Text(
                'Notifications are off for this app. Turn them on in Settings '
                'to get crew alerts.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );

  Widget _pendingChipRow(BuildContext context, ThemeData theme) => Padding(
        padding: const EdgeInsets.only(left: 16, bottom: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: context.statusColor(MissionStatus.pending)
                    .withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppColors.radiusFull),
              ),
              child: Text('Pending sync',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: context.statusColor(MissionStatus.pending))),
            ),
            gapW(8),
            Text('Changes will sync when you reconnect',
                style: theme.textTheme.labelSmall),
          ],
        ),
      );

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                )),
      );

  Widget _linkTile(BuildContext context, String label) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.chevron_right_rounded, size: 22),
        title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$label — opens in browser'))),
      );
}
