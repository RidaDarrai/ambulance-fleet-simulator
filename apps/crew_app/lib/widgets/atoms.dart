import 'package:flutter/material.dart';

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
/// `--:--` when elapsed is null (e.g. ETA unknown while route computes).
class MonoEta extends StatelessWidget {
  final Duration? elapsed;
  final double size;
  final Color? color;
  final String? suffix;

  const MonoEta(
      {super.key,
      this.elapsed,
      this.size = AppText.displaySize,
      this.color,
      this.suffix});

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
      style: etaDisplayStyle(
          size: size, color: color ?? Theme.of(context).colorScheme.onSurface),
    );
  }
}

/// Top offline strip (amber, token `color.status.assigned` family).
/// Status writes and chat queue — telemetry buffers silently (spec §14).
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final amber = context.statusColor(MissionStatus.assigned);
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
              "You're offline — status updates and messages queue and sync "
              'automatically when you reconnect.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// GPS-lost strip — distinct from offline (spec §14): position, not writes.
class GpsLostBanner extends StatelessWidget {
  const GpsLostBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final amber = context.statusColor(MissionStatus.assigned);
    return Container(
      width: double.infinity,
      color: amber.withValues(alpha: 0.14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.location_off_rounded, size: 16, color: amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'GPS signal lost — dispatch may not see your position.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Location-denied strip (persistent, from Settings/primer denial).
class LocationDeniedBanner extends StatelessWidget {
  final VoidCallback? onOpenSettings;
  const LocationDeniedBanner({super.key, this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final amber = context.statusColor(MissionStatus.assigned);
    return Container(
      width: double.infinity,
      color: amber.withValues(alpha: 0.14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.location_off_rounded, size: 16, color: amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Location off — dispatch can't see your unit. Turn it on in "
              'Settings.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (onOpenSettings != null)
            TextButton(
              onPressed: onOpenSettings,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('Open Settings'),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(message,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            FilledButton(
                onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

/// Skeleton placeholder — shimmer disabled under reduced motion.
class SkeletonBlock extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const SkeletonBlock(
      {super.key,
      this.width = double.infinity,
      this.height = 16,
      this.radius = 8});

  @override
  State<SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<SkeletonBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _shimmer.repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      child: reduce
          ? null
          : FadeTransition(
              opacity: Tween(begin: 0.55, end: 1.0).animate(
                  CurvedAnimation(parent: _shimmer, curve: Curves.easeInOut)),
              child: Container(
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(widget.radius),
                ),
              ),
            ),
    );
  }
}

// ── Spacing convenience ────────────────────────────────────────────────
SizedBox gapH(double h) => SizedBox(height: h);
SizedBox gapW(double w) => SizedBox(width: w);
