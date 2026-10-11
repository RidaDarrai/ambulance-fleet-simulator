import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/tokens.dart';
import '../widgets/atoms.dart';

/// First-run onboarding (screen spec §1).
///
/// * 3 pages max, one concept each, `Skip` visible on every page
/// * progress label "1 of 3" + dot indicator
/// * content is bundled → works fully offline; no permissions are asked here
///   (they are requested contextually in §2, after onboarding)
class OnboardingScreen extends StatefulWidget {
  final AppState state;
  const OnboardingScreen({super.key, required this.state});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  static const List<_OnbPageData> _pages = [
    _OnbPageData(
      icon: Icons.map_rounded,
      iconColor: AppColors.primary,
      surface: AppColors.medicalSurface,
      title: 'See ambulances near you, live',
      body: 'Every available unit sits on the map and updates in real time, '
          'so you always know who is closest before you ask for help.',
    ),
    _OnbPageData(
      icon: Icons.warning_amber_rounded,
      iconColor: AppColors.danger,
      surface: AppColors.dangerSurface,
      title: 'One tap to request help',
      body: 'Tap SOS to send your location straight to dispatch. A dispatcher '
          'assigns the nearest crew and you watch it move to you.',
    ),
    _OnbPageData(
      icon: Icons.local_hospital_outlined,
      iconColor: AppColors.primary,
      surface: AppColors.medicalSurface,
      title: 'Crews see your medical info sooner',
      body: 'Save blood type, allergies and emergency contacts once — they '
          'attach automatically to every request you send.',
    ),
  ];

  bool get _isLast => _index == _pages.length - 1;

  void _finish() => widget.state.completeOnboarding();

  void _next() {
    final next = _index + 1;
    // `animateToPage` with a zero duration doesn't actually move the page, so
    // jump explicitly when animations are off (e.g. the OS "reduce motion"
    // setting) — otherwise Next silently does nothing.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(next);
      return;
    }
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App name + Skip (always visible, every page)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
              child: Row(
                children: [
                  Semantics(
                    header: true,
                    child: Text('Ambulance Tracker',
                        style: theme.textTheme.labelLarge),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _finish,
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ),
            // Progress: "1 of 3"
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Semantics(
                liveRegion: true,
                child: Text('${_index + 1} of ${_pages.length}',
                    style: theme.textTheme.labelSmall),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    _OnbPage(
                      data: _pages[i],
                      semanticsLabel:
                          'Page ${i + 1} of ${_pages.length}: ${_pages[i].title}',
                    ),
                ],
              ),
            ),
            // Dot indicator
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    AnimatedContainer(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _index ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _index
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                        borderRadius:
                            BorderRadius.circular(AppColors.radiusFull),
                      ),
                    ),
                ],
              ),
            ),
            // Primary action + reassurance line
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52)),
                      onPressed: _isLast ? _finish : _next,
                      child: Text(_isLast ? 'Get started' : 'Next'),
                    ),
                  ),
                  gapH(8),
                  Text(
                    'You can change this later in Settings.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnbPageData {
  final IconData icon;
  final Color iconColor;
  final Color surface;
  final String title;
  final String body;
  const _OnbPageData({
    required this.icon,
    required this.iconColor,
    required this.surface,
    required this.title,
    required this.body,
  });
}

class _OnbPage extends StatelessWidget {
  final _OnbPageData data;
  final String semanticsLabel;
  const _OnbPage({required this.data, required this.semanticsLabel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: semanticsLabel,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              height: 188,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: data.surface,
                border: Border.all(
                    color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(AppColors.radiusLg),
              ),
              child: Icon(data.icon, size: 72, color: data.iconColor),
            ),
            gapH(24),
            Text(data.title, style: theme.textTheme.headlineLarge),
            gapH(8),
            Text(data.body,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
