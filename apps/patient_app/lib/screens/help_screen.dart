import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/tokens.dart';
import '../widgets/atoms.dart';

/// Help / FAQ + dispatcher hotline (screen spec §14).
///
/// Content is bundled → fully usable offline. Always a human path: the
/// "Call dispatcher" card is pinned at the top.
/// States: loading (accordion skeleton) · empty ("No help topics yet") ·
/// error (bundled fallback + "Showing saved help content.").
class HelpScreen extends StatefulWidget {
  final AppState state;
  const HelpScreen({super.key, required this.state});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  bool _loading = true;
  bool _bundledFallback = false; // §14 error → saved help content
  int? _open; // accordion: one open at a time

  static const _faq = <(String, String)>[
    (
      'How fast will an ambulance arrive?',
      'Dispatchers assign the nearest available unit the moment your request '
          'lands. Times vary with traffic and demand — the live ETA on your '
          'mission screen is the real number.'
    ),
    (
      'Can I request without an account?',
      'Yes. Guests can send a request and track it. Signing in just lets your '
          'medical profile attach automatically.'
    ),
    (
      "What info does the crew see?",
      'Your location, the contact number you entered and — if you attached it '
          '- your blood type, allergies and emergency contacts.'
    ),
    (
      'How do I cancel?',
      'Open the mission and tap Cancel request. You can cancel any time before '
          'a crew reaches you; we then ask you to confirm.'
    ),
    (
      'What if I have no signal?',
      'Your request is saved on the device and sends the moment you reconnect. '
          'The map keeps showing the last known positions meanwhile.'
    ),
    (
      'How accurate is the ETA?',
      'The ETA comes from the crew’s actual position and current speed, so it '
          'updates every few seconds as they move.'
    ),
  ];

  /// "How dispatch works" — 4 steps (spec §14).
  static const _how = <(String, String)>[
    ('1', 'You send a request with your location.'),
    ('2', 'A dispatcher reviews and assigns the nearest unit.'),
    ('3', 'You watch the crew move to you with a live ETA.'),
    ('4', 'The crew takes over and the mission is resolved.'),
  ];

  @override
  void initState() {
    super.initState();
    // Bundled content loads fast — brief skeleton (§14 loading).
    // The fleet-error demo toggle stands in for a failed topic fetch.
    _bundledFallback = widget.state.fleetError;
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Help'),
        actions: [
          // Share help link (spec §14 gestures).
          IconButton(
            tooltip: 'Share help link',
            icon: const Icon(Icons.ios_share_rounded, size: 20),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Help link copied'))),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _dispatcherCard(theme),
            if (_bundledFallback) ...[
              gapH(12),
              _bundledNote(theme),
            ],
            gapH(20),
            Text('How dispatch works', style: theme.textTheme.headlineMedium),
            gapH(10),
            _howSteps(theme),
            gapH(20),
            Text('Frequently asked', style: theme.textTheme.headlineMedium),
            gapH(8),
            if (_loading)
              ...List.generate(
                4,
                (_) => const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: SkeletonBlock(
                      width: double.infinity, height: 52),
                ),
              )
            else if (_faq.isEmpty)
              _emptyBlock(theme)
            else
              ..._faq.asMap().entries.map(
                    (e) => _accordion(theme, e.key, e.value.$1, e.value.$2),
                  ),
            gapH(20),
            Divider(color: theme.colorScheme.outlineVariant, height: 1),
            gapH(4),
            _linkTile(theme, 'Privacy policy', Icons.privacy_tip_outlined),
            _linkTile(theme, 'Terms of service', Icons.description_outlined),
            _linkTile(theme, 'About this app', Icons.info_outline_rounded),
            gapH(16),
          ],
        ),
      ),
    );
  }

  // ── Dispatcher card (spec §14) ───────────────────────────────────────

  Widget _dispatcherCard(ThemeData theme) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.support_agent_rounded,
                    size: 24, color: AppColors.primary),
              ),
              gapW(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Call dispatcher',
                        style: theme.textTheme.headlineSmall),
                    Text('150 · Available 24/7',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Dispatch hotline'),
                    content: const Text(
                        '150 · Emergency medical hotline\nYour location is shared on this call.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
                icon: const Icon(Icons.phone_rounded, size: 18),
                label: const Text('Tap to call'),
              ),
            ],
          ),
        ),
      );

  Widget _bundledNote(ThemeData theme) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
        ),
        child: Row(
          children: [
            Icon(Icons.offline_pin_rounded,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
            gapW(10),
            Expanded(
              child: Text('Showing saved help content.',
                  style: theme.textTheme.bodySmall),
            ),
          ],
        ),
      );

  // ── How dispatch works (4-step graphic) ──────────────────────────────

  Widget _howSteps(ThemeData theme) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.medicalSurface,
          border: Border.all(color: AppColors.medicalBorder),
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
        ),
        child: Column(
          children: [
            for (var i = 0; i < _how.length; i++)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Text(_how[i].$1,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                  gapW(12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(_how[i].$2,
                          style: theme.textTheme.bodySmall),
                    ),
                  ),
                ],
              ),
          ],
        ),
      );

  // ── FAQ accordion (one open at a time, spec §14) ─────────────────────

  Widget _accordion(ThemeData theme, int i, String q, String a) {
    final open = _open == i;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: open
            ? theme.colorScheme.surfaceContainerLowest
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          initiallyExpanded: open,
          onExpansionChanged: (v) => setState(() => _open = v ? i : null),
          title: Text(q, style: theme.textTheme.bodyMedium),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(a, style: theme.textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty + links ────────────────────────────────────────────────────

  Widget _emptyBlock(ThemeData theme) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
        ),
        child: Column(
          children: [
            Text('No help topics yet',
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center),
            gapH(4),
            Text('You can still reach a dispatcher any time.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center),
            gapH(12),
            FilledButton.tonalIcon(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Dialing 150…'))),
              icon: const Icon(Icons.phone_rounded, size: 18),
              label: const Text('Call dispatcher'),
            ),
          ],
        ),
      );

  Widget _linkTile(ThemeData theme, String label, IconData icon) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        title: Text(label, style: theme.textTheme.bodyMedium),
        trailing: Icon(Icons.chevron_right_rounded,
            size: 20, color: theme.colorScheme.outline),
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$label — opens in browser'))),
      );
}
