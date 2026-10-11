import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/mission_status.dart';
import '../core/tokens.dart';
import '../theme/app_theme.dart';

/// One-liner status pill: colored dot + label. Token: `color.status.*`.
class StatusChip extends StatelessWidget {
  final MissionStatus status;
  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = context.statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppColors.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(status.label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

/// ETA countdown — mono, bold, tabular digits (token `type.display.mono`).
/// `--:--` when elapsed is null (e.g. ETA unknown while pending).
class MonoEta extends StatelessWidget {
  final Duration? elapsed;
  final double size;
  final Color? color;
  final String? suffix;

  const MonoEta({super.key, this.elapsed, this.size = AppText.displaySize, this.color, this.suffix});

  static String _mmSs(Duration d) {
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final txt = elapsed == null ? '--:--' : _mmSs(elapsed!);
    return Text(
      suffix == null ? txt : '$txt $suffix',
      style: etaDisplayStyle(size: size, color: color ?? Theme.of(context).colorScheme.onSurface),
    );
  }
}

/// Floating SOS button — token `panic.size` 72px, `color.danger`.
/// Pulse ring disabled when the user prefers reduced motion (Settings → demo).
class PanicButton extends StatefulWidget {
  final VoidCallback? onPressed;

  const PanicButton({super.key, this.onPressed});

  @override
  State<PanicButton> createState() => _PanicButtonState();
}

class _PanicButtonState extends State<PanicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    _pulse.repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduced-motion handling (design-tokens §6).
    final MediaQueryData mq = MediaQuery.of(context);
    final reduce = mq.disableAnimations;
    return GestureDetector(
      onTap: widget.onPressed,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!reduce)
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final t = Curves.easeOut.transform(_pulse.value);
                return Container(
                  width: AppColors.panicSize + (t * 20),
                  height: AppColors.panicSize + (t * 20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.danger.withValues(alpha: 0.45 - t * 0.45)),
                  ),
                );
              },
            ),
          Container(
            width: AppColors.panicSize,
            height: AppColors.panicSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.danger,
              boxShadow: [
                BoxShadow(
                  color: AppColors.danger.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Center(
              child: Text('SOS',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Top offline strip (amber, token `color.status.pending` family).
/// Requests keep working — they queue and send when reconnected.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final amber = context.statusColor(MissionStatus.pending);
    return Container(
      width: double.infinity,
      color: amber.withValues(alpha: 0.14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 16, color: amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "You're offline — requests queue and send automatically when you reconnect.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Canonical empty state (4 parts): visual → heading → message → action.
class EmptyStateBox extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyStateBox({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.primary.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pulse-skeleton loading block (token `surface.muted`).
class SkeletonBlock extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const SkeletonBlock({
    super.key,
    required this.width,
    required this.height,
    this.radius = AppColors.radiusMd,
  });

  @override
  State<SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<SkeletonBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900), lowerBound: 0.4, upperBound: 1.0)
    ..repeat(reverse: true);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctl,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Medical summary card (token `medical.surface` / `medical.border`).
class MedicalCard extends StatelessWidget {
  final MedicalProfile profile;
  final bool dark;

  const MedicalCard({super.key, required this.profile, this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark
            ? AppColors.primary.withValues(alpha: 0.12)
            : AppColors.medicalSurface,
        border: Border.all(
            color: dark
                ? AppColors.primary.withValues(alpha: 0.35)
                : AppColors.medicalBorder),
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Medical profile attached',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 2),
          Text(
            [
              profile.bloodType ?? 'Blood type not added',
              profile.allergies.isEmpty
                  ? 'no known allergies'
                  : profile.allergies.join(', '),
              '${profile.contacts.length} contact${profile.contacts.length == 1 ? '' : 's'}',
            ].join(' · '),
            style: Theme.of(context).textTheme.headlineSmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Spacing convenience ────────────────────────────────────────────────
SizedBox gapH(double h) => SizedBox(height: h);
SizedBox gapW(double w) => SizedBox(width: w);