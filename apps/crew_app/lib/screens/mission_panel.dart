import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_state.dart';
import '../core/mission_status.dart';
import '../core/tokens.dart';
import '../theme/app_theme.dart';
import '../widgets/atoms.dart';
import 'chat_screen.dart';

/// Active mission panel (spec §6) — the same widget in both compositions:
/// inside the phone bottom sheet and inside the tablet side panel. The app
/// theme is already dark while a mission is active (hybrid rule), so this
/// widget always renders on the dark surface.
class MissionPanel extends StatefulWidget {
  final AppState state;
  final bool tablet;
  const MissionPanel({super.key, required this.state, this.tablet = false});

  @override
  State<MissionPanel> createState() => _MissionPanelState();
}

class _MissionPanelState extends State<MissionPanel> {
  AppState get state => widget.state;

  Future<void> _advance() async {
    final m = state.activeMission!;
    final wasResolved = m.status == MissionStatus.atHospital;
    final ok = await state.advanceStatus();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't update status. Try again.")));
    } else if (wasResolved) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Mission completed — logged in History.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = state.activeMission!;
    final color = context.statusColor(m.status);
    final blocked = state.actionBlockedByHospital(m.status);
    final moving = m.status == MissionStatus.accepted ||
        m.status == MissionStatus.enRoute ||
        m.status == MissionStatus.transporting;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.offline) ...[const OfflineBanner(), gapH(8)],
        if (state.gpsLost) ...[const GpsLostBanner(), gapH(8)],

        // ── Phase strip (full-width 5px, tablet; header strip, phone) ──
        Container(
          height: 5,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        gapH(12),

        // ── Header: status label + unit + pending chip ────────────────
        Row(
          children: [
            Icon(Icons.local_hospital_rounded, size: 16, color: color),
            gapW(8),
            Expanded(
              child: Text(m.status.stripLabel,
                  style: theme.textTheme.labelLarge?.copyWith(color: color)),
            ),
            if (m.offlinePending)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context
                      .statusColor(MissionStatus.assigned)
                      .withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppColors.radiusFull),
                ),
                child: Text('Pending sync',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: context.statusColor(MissionStatus.assigned))),
              ),
            gapW(8),
            Text(state.ambulanceId,
                style: etaDisplayStyle(size: 13, color: Colors.white70)),
          ],
        ),
        gapH(14),

        // ── Hero readout: ETA + distance ──────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.status == MissionStatus.onScene
                        ? 'On scene'
                        : m.hospitalName ?? 'Patient pickup',
                    style: theme.textTheme.headlineSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  gapH(2),
                  // On-scene / transport duration chip (mono, spec §6).
                  if (m.status == MissionStatus.onScene &&
                      m.timeline[MissionStatus.onScene] != null)
                    _ElapsedChip(
                        since: m.timeline[MissionStatus.onScene]!,
                        label: 'On scene')
                  else if (m.status == MissionStatus.transporting &&
                      m.timeline[MissionStatus.transporting] != null)
                    _ElapsedChip(
                        since: m.timeline[MissionStatus.transporting]!,
                        label: 'Transporting'),
                ],
              ),
            ),
            if (moving) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('ETA', style: theme.textTheme.labelSmall),
                  MonoEta(
                      elapsed: Duration(seconds: m.etaSeconds),
                      size: widget.tablet ? 36 : 30,
                      color: color),
                ],
              ),
              gapW(16),
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('DIST', style: theme.textTheme.labelSmall),
                Text(
                  m.distanceKm <= 0
                      ? '—'
                      : '${m.distanceKm.toStringAsFixed(1)} km',
                  style: etaDisplayStyle(
                      size: widget.tablet ? 36 : 30,
                      color: theme.colorScheme.onSurface),
                ),
              ],
            ),
          ],
        ),
        gapH(14),

        // ── 5-dot stepper (accepted → atHospital) ─────────────────────
        _Stepper(status: m.status),
        gapH(14),

        // ── Patient card row (tap → sheet §7) ─────────────────────────
        _PatientRow(patient: m.patient, status: m.status),
        gapH(10),

        // ── Hospital picker (from onScene; inline card, spec §8) ──────
        if (m.status == MissionStatus.onScene) ...[
          _HospitalCard(state: state),
          gapH(10),
        ],

        // ── Comms row (§9) ────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _CommsButton(
                icon: Icons.phone_rounded,
                label: 'Patient',
                enabled: m.patient.contactPhone != null,
                onTap: m.patient.contactPhone == null
                    ? null
                    : () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Dialing patient…'))),
              ),
            ),
            gapW(8),
            Expanded(
              child: _CommsButton(
                icon: Icons.support_agent_rounded,
                label: 'Dispatch',
                enabled: true,
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Dialing dispatch hotline 150…'))),
              ),
            ),
            gapW(8),
            Expanded(
              child: _CommsButton(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Chat',
                enabled: true,
                badge: state.unreadCount(m.id),
                onTap: () {
                  state.openChat(m.id);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            ChatScreen(state: state, missionId: m.id)),
                  );
                },
              ),
            ),
          ],
        ),
        gapH(14),

        // ── One next action (never disabled without a reason) ─────────
        if (blocked) ...[
          Text('Pick a hospital first',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: context.statusColor(MissionStatus.assigned))),
          gapH(8),
        ],
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: Size.fromHeight(widget.tablet ? 60 : 56),
            backgroundColor: m.status == MissionStatus.atHospital
                ? AppColors.statusResolved
                : color,
          ),
          onPressed: m.offlinePending || blocked ? null : _advance,
          child: m.offlinePending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(m.status.actionLabel),
        ),
      ],
    );
  }
}

// ── 5-dot stepper ──────────────────────────────────────────────────────

class _Stepper extends StatelessWidget {
  final MissionStatus status;
  const _Stepper({required this.status});

  @override
  Widget build(BuildContext context) {
    final current = status.stepIndex;
    return Row(
      children: List.generate(5, (i) {
        final done = current != null && i < current;
        final active = i == current;
        final color = context.statusColor(status);
        return Expanded(
          child: Container(
            height: 5,
            margin: EdgeInsets.only(right: i == 4 ? 0 : 4),
            decoration: BoxDecoration(
              color: done
                  ? AppColors.statusResolved
                  : active
                      ? color
                      : (Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF1E293B)
                          : AppColors.border),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }
}

// ── On-scene / transport elapsed chip ──────────────────────────────────

class _ElapsedChip extends StatelessWidget {
  final DateTime since;
  final String label;
  const _ElapsedChip({required this.since, required this.label});

  @override
  Widget build(BuildContext context) {
    final d = DateTime.now().difference(since);
    final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return Text('$label $mm:$ss',
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]));
  }
}

// ── Patient row ────────────────────────────────────────────────────────

class _PatientRow extends StatelessWidget {
  final PatientProfile patient;
  final MissionStatus status;
  const _PatientRow({required this.patient, required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppColors.radiusMd),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => _PatientSheet(patient: patient),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.10),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.30)),
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
        ),
        child: Row(
          children: [
            const Icon(Icons.medical_information_outlined,
                size: 20, color: AppColors.primary),
            gapW(10),
            Expanded(
              child: Text(
                patient.isGuest
                    ? 'Guest caller · no profile'
                    : '${patient.bloodType ?? '—'} · '
                        '${patient.allergies.isEmpty ? 'no allergies' : '${patient.allergies.first} allergy'}',
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

class _PatientSheet extends StatelessWidget {
  final PatientProfile patient;
  const _PatientSheet({required this.patient});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            Text(patient.isGuest ? 'Guest caller' : 'Patient',
                style: theme.textTheme.headlineSmall),
            gapH(4),
            Text('Provided by the patient',
                style: theme.textTheme.labelSmall),
            gapH(14),
            if (patient.isGuest)
              Text('No medical profile shared',
                  style: theme.textTheme.bodyMedium)
            else ...[
              Text(patient.bloodType ?? 'Blood type not added',
                  style: etaDisplayStyle(size: 28)),
              gapH(10),
              Text('Allergies', style: theme.textTheme.labelLarge),
              gapH(4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: patient.allergies.isEmpty
                    ? [const Text('None reported')]
                    : patient.allergies
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
                children: patient.conditions.isEmpty
                    ? [const Text('None reported')]
                    : patient.conditions
                        .map((c) => Chip(
                              label: Text(c),
                              visualDensity: VisualDensity.compact,
                            ))
                        .toList(),
              ),
              gapH(10),
              if (patient.contacts.isNotEmpty) ...[
                Text('Emergency contacts', style: theme.textTheme.labelLarge),
                gapH(4),
                Text(patient.contacts.first,
                    style: theme.textTheme.bodyMedium),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// ── Hospital picker card (§8) ──────────────────────────────────────────

class _HospitalCard extends StatelessWidget {
  final AppState state;
  const _HospitalCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = state.activeMission!;
    final selected = state.hospitals
        .where((h) => h.id == m.hospitalId)
        .toList();
    return InkWell(
      borderRadius: BorderRadius.circular(AppColors.radiusMd),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => _HospitalSheet(state: state),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.35),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
        ),
        child: Row(
          children: [
            Icon(Icons.local_hospital_rounded,
                size: 20, color: context.statusColor(m.status)),
            gapW(10),
            Expanded(
              child: Text(
                selected.isEmpty
                    ? 'Destination hospital'
                    : selected.first.name,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Text(selected.isEmpty ? 'Pick' : 'Change',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.primary)),
          ],
        ),
      ),
    );
  }
}

class _HospitalSheet extends StatelessWidget {
  final AppState state;
  const _HospitalSheet({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = state.activeMission!;
    final sorted = [...state.hospitals]
      ..sort((a, b) {
        final da = const Distance()
            .as(LengthUnit.Kilometer, m.pickup, a.location);
        final db = const Distance()
            .as(LengthUnit.Kilometer, m.pickup, b.location);
        return da.compareTo(db);
      });
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
            Text('Destination hospital', style: theme.textTheme.headlineSmall),
            gapH(4),
            Text('Destination can be changed until transport starts.',
                style: theme.textTheme.labelSmall),
            gapH(10),
            if (state.hospitals.isEmpty)
              EmptyStateBox(
                icon: Icons.local_hospital_outlined,
                title: 'No hospitals configured',
                message: 'Call dispatch to coordinate the destination.',
                actionLabel: 'Call dispatch',
                onAction: () => Navigator.of(context).pop(),
              )
            else
              ...sorted.map((h) {
                final km = const Distance()
                    .as(LengthUnit.Kilometer, m.pickup, h.location);
                final selected = h.id == m.hospitalId;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.local_hospital_outlined,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                  title: Text(h.name),
                  trailing: Text('${km.toStringAsFixed(1)} km',
                      style: etaDisplayStyle(
                          size: 14, color: theme.colorScheme.onSurface)),
                  onTap: () {
                    state.pickHospital(h);
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            '${h.name} — transport unlocked')));
                  },
                );
              }),
          ],
        ),
      ),
    );
  }
}

// ── Comms button ───────────────────────────────────────────────────────

class _CommsButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final int badge;
  final VoidCallback? onTap;
  const _CommsButton({
    required this.icon,
    required this.label,
    required this.enabled,
    this.badge = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppColors.radiusMd),
      onTap: enabled ? onTap : null,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.35),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 18,
                    color: enabled
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.outline),
                gapH(2),
                Text(label,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: enabled
                            ? null
                            : theme.colorScheme.outline)),
              ],
            ),
            if (badge > 0)
              Positioned(
                top: 6,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius:
                        BorderRadius.circular(AppColors.radiusFull),
                  ),
                  child: Text('$badge',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
