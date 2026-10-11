import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/account_screen.dart';
import 'screens/login_screen.dart';
import 'screens/mission_screen.dart';
import 'screens/ops_screen.dart';
import 'services/crew_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const CrewApp());
}

class CrewApp extends StatelessWidget {
  const CrewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ambulance Crew',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const RootGate(),
    );
  }
}

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: CrewService().authChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snapshot.data;
        if (user == null) return const LoginScreen();
        return HomeShell(user: user);
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.user});

  final User user;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _service = CrewService();
  String? _ambulanceId;
  String _plate = '';
  bool _loading = true;
  int _index = 0;

  /// Dev-only override: switches the active vehicle without re-login.
  String? _devOverrideId;
  String? _devOverridePlate;
  List<Map<String, String>> _fleet = const [];
  StreamSubscription<List<Map<String, String>>>? _fleetSub;

  static const _titles = ['Operations', 'Mission', 'Account'];

  bool get _devSwitcher => kDebugMode;

  /// Vehicle the UI currently shows (dev override wins over account vehicle).
  String? get _activeId => _devOverrideId ?? _ambulanceId;

  String get _activePlate => _devOverridePlate ?? _plate;

  @override
  void initState() {
    super.initState();
    _load();
    if (_devSwitcher) {
      _fleetSub = _service.watchAllAmbulances().listen((fleet) {
        if (mounted) setState(() => _fleet = fleet);
      });
    }
  }

  @override
  void dispose() {
    _fleetSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final id = await _service.myAmbulanceId(widget.user.uid);
    String plate = '';
    if (id != null) {
      final amb = await _service.ambulance(id);
      plate = amb?['plate'] as String? ?? '';
    }
    if (mounted) {
      setState(() {
        _ambulanceId = id;
        _plate = plate;
        if (_devSwitcher && id != null && _devOverrideId == null) {
          _devOverrideId = id;
          _devOverridePlate = plate;
        }
        _loading = false;
      });
    }
  }

  void _selectVehicle(Map<String, String> entry) {
    setState(() {
      _devOverrideId = entry['id'];
      _devOverridePlate = entry['plate'];
      _index = 0;
    });
  }

  Widget _devSwitcherButton() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.local_hospital),
      tooltip: 'DEV: switch vehicle',
      onSelected: (id) {
        final entry = _fleet.firstWhere((e) => e['id'] == id,
            orElse: () => <String, String>{});
        if (entry.isNotEmpty) _selectVehicle(entry);
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          enabled: false,
          child: Text('DEV — switch vehicle',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        ..._fleet.map((e) => PopupMenuItem<String>(
              value: e['id'],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle,
                      size: 10,
                      color: e['status'] == 'active'
                          ? Colors.green
                          : Colors.orange),
                  const SizedBox(width: 8),
                  Text(e['plate'] ?? ''),
                  if (e['id'] == _activeId) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.check, size: 16),
                  ],
                ],
              ),
            )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final activeId = _activeId;
    if (activeId == null) {
      // No vehicle linked: release builds stop here; dev builds still get the
      // switcher in the app bar so a vehicle can be picked.
      return Scaffold(
        appBar: _devSwitcher && _fleet.isNotEmpty
            ? AppBar(actions: [_devSwitcherButton()])
            : null,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No ambulance is assigned to ${widget.user.email}.\n'
              'Ask the administrator to assign one.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          if (_devSwitcher && _fleet.isNotEmpty) _devSwitcherButton(),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          OpsScreen(key: ValueKey(activeId), ambulanceId: activeId),
          MissionScreen(key: ValueKey(activeId), ambulanceId: activeId),
          AccountScreen(
            key: ValueKey(activeId),
            user: widget.user,
            ambulanceId: activeId,
            plate: _activePlate,
            devOverride: _devSwitcher && _devOverrideId != _ambulanceId,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Ops'),
          BottomNavigationBarItem(
              icon: Icon(Icons.local_hospital), label: 'Mission'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Account'),
        ],
      ),
    );
  }
}
