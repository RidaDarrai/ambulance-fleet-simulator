import 'package:flutter/material.dart';

import 'atoms.dart';

/// Crew location primer (spec §2) — single card, no carousel. Crew are
/// trained staff; this explains telemetry before the OS dialog once.
Future<bool?> showLocationPrimer(BuildContext context) {
  return showPermissionPrimer(
    context,
    icon: Icons.my_location_rounded,
    title: 'Your location keeps dispatch accurate',
    reason: "We send your position while you're on duty so dispatchers see "
        'the nearest unit. You can turn it off anytime in Settings.',
    allowLabel: 'Enable location',
    laterLabel: 'Not now',
    whyTitle: 'Why precise location?',
    whyBody: 'Dispatch routes the closest available unit using your live '
        'position. Without it, your unit may not be dispatched.',
  );
}

/// Pre-permission explainer (screen spec §2).
///
/// Always shown *before* the OS dialog so the reason is understood first, and
/// "Not now" keeps the ability to ask again later. Returns:
///   `true`  → user tapped the allow button
///   `false` → user chose "Not now"
///   `null`  → sheet dismissed (drag / outside tap)
Future<bool?> showPermissionPrimer(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String reason,
  required String allowLabel,
  required String laterLabel,
  String whyTitle = 'Why we ask',
  required String whyBody,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isDismissible: true,
    enableDrag: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 28, color: theme.colorScheme.primary),
              ),
              gapH(16),
              Text(title, style: theme.textTheme.headlineMedium),
              gapH(8),
              Text(reason,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              gapH(20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: Text(allowLabel),
                ),
              ),
              gapH(4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    child: Text(laterLabel),
                  ),
                  TextButton(
                    onPressed: () => showDialog<void>(
                      context: sheetContext,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(whyTitle),
                        content: Text(whyBody),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ),
                    child: const Text('Why we ask'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
