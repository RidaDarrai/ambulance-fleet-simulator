import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/mission_status.dart';
import '../core/tokens.dart';
import '../theme/app_theme.dart';
import '../widgets/atoms.dart';

/// Account (spec §13) — identity, shift truth, and the few settings crew
/// actually own. Tablet: single centered pane (max 560dp).
class AccountScreen extends StatelessWidget {
  final AppState state;
  const AccountScreen({super.key, required this.state});

  String _shiftRemaining() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 20); // demo 20:00
    final d = end.difference(now);
    if (d.isNegative) return '0:00:00';
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final green = context.statusColor(MissionStatus.resolved);
    final amber = context.statusColor(MissionStatus.assigned);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Identity card ────────────────────────────────────────
              _Section(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: theme.colorScheme.primary.withValues(
                            alpha: 0.12,
                          ),
                          child: Icon(
                            Icons.person_rounded,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        gapW(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                state.crewName,
                                style: theme.textTheme.titleLarge,
                              ),
                              gapH(2),
                              Text(
                                state.crewEmail,
                                style: theme.textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(
                              AppColors.radiusFull,
                            ),
                          ),
                          child: Text(
                            'CREW',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    gapH(14),
                    const Divider(height: 1),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.local_hospital_outlined,
                        size: 22,
                      ),
                      title: const Text('Vehicle'),
                      trailing: Text(
                        state.ambulanceId,
                        style: etaDisplayStyle(size: 16),
                      ),
                    ),
                  ],
                ),
              ),
              gapH(16),

              // ── Shift card ───────────────────────────────────────────
              _Section(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Today’s shift',
                            style: theme.textTheme.labelLarge,
                          ),
                          gapH(4),
                          Text(
                            '08:00–20:00',
                            style: theme.textTheme.titleMedium,
                          ),
                          gapH(4),
                          Text(
                            'Breaks are logged with dispatch.',
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Remaining', style: theme.textTheme.labelSmall),
                        gapH(2),
                        Text(
                          _shiftRemaining(),
                          style: etaDisplayStyle(size: 20),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              gapH(16),

              // ── Notifications ────────────────────────────────────────
              _Section(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Notifications', style: theme.textTheme.labelLarge),
                    gapH(4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mission alerts'),
                      subtitle: state.onDuty
                          ? const Text(
                              'Locked on while you’re on duty — jobs can’t '
                              'be missed.',
                            )
                          : null,
                      value: true,
                      onChanged: state.onDuty ? null : (_) {},
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Sound'),
                      value: state.soundEnabled,
                      onChanged: state.setSound,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Respect quiet hours'),
                      subtitle: const Text(
                        'Alerts stay silent outside your shift.',
                      ),
                      value: state.respectQuietHours,
                      onChanged: state.setRespectQuietHours,
                    ),
                  ],
                ),
              ),
              gapH(16),

              // ── Permissions ──────────────────────────────────────────
              _Section(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Permissions', style: theme.textTheme.labelLarge),
                    gapH(4),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        state.locationGranted
                            ? Icons.my_location_rounded
                            : Icons.location_off_rounded,
                        size: 22,
                        color: state.locationGranted ? green : amber,
                      ),
                      title: const Text('Location'),
                      subtitle: Text(
                        state.locationGranted
                            ? 'While on duty, your position is shared with dispatch.'
                            : 'Dispatch can’t see your unit. Open settings to allow '
                                  'location.',
                      ),
                      trailing: state.locationGranted
                          ? null
                          : TextButton(
                              onPressed: () => state.setLocationGranted(true),
                              child: const Text('Open Settings'),
                            ),
                    ),
                  ],
                ),
              ),
              gapH(16),

              // ── About ────────────────────────────────────────────────
              _Section(
                child: Column(
                  children: [
                    _AboutRow(
                      icon: Icons.info_outline_rounded,
                      label: 'App version',
                      value: 'v0.1 (design demo)',
                    ),
                    _AboutRow(
                      icon: Icons.phone_rounded,
                      label: 'Dispatcher hotline',
                      value: '150',
                      mono: true,
                    ),
                    _AboutRow(
                      icon: Icons.privacy_tip_outlined,
                      label: 'Privacy policy',
                      chevron: true,
                    ),
                    _AboutRow(
                      icon: Icons.description_outlined,
                      label: 'Terms of service',
                      chevron: true,
                    ),
                  ],
                ),
              ),
              gapH(16),

              // ── Sign out (danger text) ───────────────────────────────
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: () => _signOut(context),
                icon: const Icon(Icons.logout_rounded, size: 20),
                label: const Text('Sign out'),
              ),
              if (!state.canSignOut)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'You have an active mission. Finish it before signing out.',
                    style: theme.textTheme.labelSmall,
                    textAlign: TextAlign.center,
                  ),
                ),
              gapH(24),

              // ── Demo panel (state review) ────────────────────────────
              _DemoPanel(state: state),
              gapH(24),
            ],
          ),
        ),
      ),
    );
  }

  void _signOut(BuildContext context) {
    if (!state.canSignOut) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Active mission'),
          content: const Text(
            'You have an active mission. Finish it before signing out.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You’ll stop receiving jobs until you sign in '
          'and go on duty again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              state.signOut();
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final Widget child;
  const _Section({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
      ),
      // ListTiles inside need a Material ancestor for their ink.
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

class _AboutRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final bool mono;
  final bool chevron;
  const _AboutRow({
    required this.icon,
    required this.label,
    this.value,
    this.mono = false,
    this.chevron = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, size: 20),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Text(
              value!,
              style: mono
                  ? etaDisplayStyle(size: 14)
                  : Theme.of(context).textTheme.labelSmall,
            ),
          if (chevron)
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.outline,
            ),
        ],
      ),
      onTap: () =>
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$label — demo stub'))),
    );
  }
}

/// Demo-only state review panel (spec §14 states on demand).
class _DemoPanel extends StatelessWidget {
  final AppState state;
  const _DemoPanel({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ExpansionTile(
          shape: const Border(),
          leading: const Icon(Icons.science_outlined, size: 20),
          title: Text('State (demo)', style: theme.textTheme.labelLarge),
          subtitle: Text(
            'Review the spec’d states on demand.',
            style: theme.textTheme.labelSmall,
          ),
          children: [
            SwitchListTile(
              title: const Text('Simulate offline'),
              subtitle: const Text('Status writes queue with pending chip.'),
              value: state.offline,
              onChanged: state.setOffline,
            ),
            SwitchListTile(
              title: const Text('GPS signal lost'),
              subtitle: const Text('Amber strip (distinct from offline).'),
              value: state.gpsLost,
              onChanged: state.setGpsLost,
            ),
            SwitchListTile(
              title: const Text('Location denied'),
              subtitle: const Text('Persistent strip + Open Settings.'),
              value: !state.locationGranted,
              onChanged: (v) => state.setLocationGranted(!v),
            ),
            SwitchListTile(
              title: const Text('Fleet map error'),
              subtitle: const Text('Map area shows error + Retry.'),
              value: state.fleetError,
              onChanged: state.setFleetError,
            ),
            SwitchListTile(
              title: const Text('Vehicle not mapped'),
              subtitle: const Text('Blocking card: call dispatch.'),
              value: state.vehicleUnmapped,
              onChanged: state.setVehicleUnmapped,
            ),
            SwitchListTile(
              title: const Text('History loading'),
              subtitle: const Text('Five skeleton rows (spec §11).'),
              value: state.historyLoading,
              onChanged: state.setHistoryLoading,
            ),
            SwitchListTile(
              title: const Text('History error'),
              subtitle: const Text('Error card + Retry (spec §11).'),
              value: state.historyError,
              onChanged: state.setHistoryError,
            ),
            SwitchListTile(
              title: const Text('Simulate duty error'),
              subtitle: const Text('Toggle reverts + snackbar (spec §4).'),
              value: state.simulateDutyError,
              onChanged: state.setDutyError,
            ),
            SwitchListTile(
              title: const Text('Simulate mission write error'),
              subtitle: const Text('Action reverts + snackbar (spec §6).'),
              value: state.simulateMissionWriteError,
              onChanged: state.setMissionWriteError,
            ),
            SwitchListTile(
              title: const Text('Simulate login error'),
              subtitle: const Text('Sign-in always fails (spec §1).'),
              value: state.simulateLoginError,
              onChanged: state.setLoginError,
            ),
            SwitchListTile(
              title: const Text('Expire session'),
              subtitle: const Text('Back to login with banner (spec §14).'),
              value: state.sessionExpired,
              onChanged: (v) => v
                  ? state.expireSession()
                  : state.signIn(state.crewEmail, 'crew12345'),
            ),
            SwitchListTile(
              title: const Text('Reduce motion'),
              subtitle: const Text('Disables pulse + shimmer.'),
              value: state.reduceMotion,
              onChanged: state.setReduceMotion,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.refresh_rounded, size: 22),
              title: const Text('Replay location primer'),
              onTap: () => state.completeLocationPrimer(granted: false),
            ),
          ],
        ),
      ),
    );
  }
}
