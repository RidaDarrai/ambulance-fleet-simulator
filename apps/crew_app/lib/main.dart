import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'core/mission_status.dart';
import 'firebase_options.dart';
import 'screens/account_screen.dart';
import 'screens/history_screen.dart';
import 'screens/login_screen.dart';
import 'screens/ops_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/permission_primer.dart';

/// Note: when the crew-side `FirebaseRepository` is built (mirroring
/// patient_app), gate it behind a `--dart-define=LIVE=true` flag plus a
/// `Firebase.apps.isNotEmpty` check and pass it to `AppState(repository: …)`.
/// Until then the app boots on the in-memory demo repository, so UI
/// walkthroughs need no backend.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase is OPTIONAL at boot. If init fails (offline, unsupported
  // platform, bad config) the app still runs in demo mode — the repository
  // seam means no screen touches Firebase until a FirebaseRepository is
  // installed via AppState.useRepository().
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('Firebase unavailable — staying in demo mode: $e');
  }

  runApp(const CrewApp());
}

/// Adaptive breakpoint (IA §0.5): mounted landscape tablets get the rail +
/// side-panel composition; everything else keeps the phone layout.
bool isTabletLayout(BuildContext context) {
  final mq = MediaQuery.of(context);
  return mq.orientation == Orientation.landscape &&
      mq.size.shortestSide >= 600;
}

class CrewApp extends StatefulWidget {
  const CrewApp({super.key});

  @override
  State<CrewApp> createState() => _CrewAppState();
}

class _CrewAppState extends State<CrewApp> {
  // Demo repository by default; `repository:` param is the seam for the
  // future FirebaseRepository (gated behind LIVE + Firebase.apps check).
  final _state = AppState();

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        // Hybrid rule (approved): calm at rest, dark cockpit from `assigned`
        // through `atHospital` — driven by mission state, never a setting.
        final mission = _state.activeMission;
        final darkMission = mission != null &&
            mission.status != MissionStatus.resolved;
        return MaterialApp(
          title: 'Ambulance Crew',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(brightness: Brightness.light),
          darkTheme: buildAppTheme(brightness: Brightness.dark),
          themeMode: darkMission ? ThemeMode.dark : ThemeMode.light,
          home: _state.isSignedIn
              ? RootGate(state: _state)
              : LoginScreen(state: _state),
        );
      },
    );
  }
}

class RootGate extends StatefulWidget {
  final AppState state;
  const RootGate({super.key, required this.state});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  int _tab = 0; // 0 Ops · 1 History · 2 Account
  bool _primerShown = false;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    // First-launch location primer (§2) — once, before the deck.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePrimer());
  }

  Future<void> _maybePrimer() async {
    if (_primerShown || state.locationPrimerShown) return;
    _primerShown = true;
    final granted = await showLocationPrimer(context);
    if (!mounted) return;
    state.completeLocationPrimer(granted: granted ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final tablet = isTabletLayout(context);
    final screens = [
      OpsScreen(state: state),
      HistoryScreen(state: state),
      AccountScreen(state: state),
    ];

    return Scaffold(
      body: Row(
        children: [
          if (tablet)
            NavigationRail(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Icon(Icons.local_hospital_rounded,
                    color: Theme.of(context).colorScheme.primary),
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map_rounded),
                  label: Text('Ops'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.history_rounded),
                  label: Text('History'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: Text('Account'),
                ),
              ],
            ),
          Expanded(child: screens[_tab]),
        ],
      ),
      bottomNavigationBar: tablet
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map_rounded),
                  label: 'Ops',
                ),
                NavigationDestination(
                  icon: Icon(Icons.history_rounded),
                  label: 'History',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: 'Account',
                ),
              ],
            ),
    );
  }
}
