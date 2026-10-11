import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'core/mission_status.dart';
import 'screens/fleet_screen.dart';
import 'screens/mission_screen.dart';
import 'screens/missions_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/profile_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/atoms.dart';
import 'widgets/permission_primer.dart';

void main() => runApp(const PatientApp());

class PatientApp extends StatefulWidget {
  const PatientApp({super.key});
  @override
  State<PatientApp> createState() => _PatientAppState();
}

class _PatientAppState extends State<PatientApp> {
  late final AppState _state = AppState();

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) => MaterialApp(
        title: 'Ambulance Tracker',
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: _state.themeMode,
        home: _state.onboardingDone
            ? AppShell(state: _state)
            : OnboardingScreen(state: _state),
      ),
    );
  }
}

/// Root tabs + simulated FCM push: when a request reaches `dispatched`,
/// a mission route opens automatically (deep-link behavior, IA §3.6).
class AppShell extends StatefulWidget {
  final AppState state;
  const AppShell({super.key, required this.state});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  String? _openedIncident;

  AppState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    _state.addListener(_onStateChange);
    // Contextual permission: explain location *before* the OS dialog the
    // first time the map appears (screen spec §2).
    _maybeShowLocationPrimer();
  }

  Future<void> _maybeShowLocationPrimer() async {
    if (_state.locationPrimerShown) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final granted = await showPermissionPrimer(
      context,
      icon: Icons.my_location_rounded,
      title: 'Share your location so we can send the nearest ambulance',
      reason: 'We use it to place your pin on the map and route the closest '
          'crew. It is only shared while a request is active.',
      allowLabel: 'Allow location',
      laterLabel: 'Not now',
      whyTitle: 'Why location matters',
      whyBody: 'Dispatch needs your position to find you and to route the '
          'ambulance to you. Without it you can still send a request, but you '
          'will need to describe your pickup point manually.',
    );
    if (!mounted) return;
    _state.completeLocationPrimer(granted: granted ?? false);
  }

  @override
  void dispose() {
    _state.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange() {
    final inc = _state.activeIncident;
    if (inc == null) {
      _openedIncident = null;
      return;
    }
    if (inc.status != MissionStatus.dispatched || _openedIncident == inc.id) {
      return;
    }
    _openedIncident = inc.id;
    final nav = Navigator.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !nav.canPop()) {
        nav.push(MaterialPageRoute(builder: (_) => MissionScreen(state: _state)));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveMission = _state.activeIncident != null &&
        _state.activeIncident!.status != MissionStatus.resolved;

    return Scaffold(
      body: Column(
        children: [
          if (_state.offline) const OfflineBanner(),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                FleetScreen(state: _state),
                MissionsScreen(
                  state: _state,
                  onGoToMap: () => setState(() => _index = 0),
                ),
                ProfileScreen(state: _state),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: _state,
        builder: (context, _) => NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map_rounded),
              label: 'Map',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: hasActiveMission,
                child: const Icon(Icons.route_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: hasActiveMission,
                child: const Icon(Icons.route_rounded),
              ),
              label: 'Missions',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}