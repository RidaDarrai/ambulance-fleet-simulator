import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/crew_service.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    required this.user,
    required this.ambulanceId,
    required this.plate,
    this.devOverride = false,
  });

  final User user;
  final String ambulanceId;
  final String plate;
  final bool devOverride;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.local_hospital),
            title: Text(user.email ?? 'Crew'),
            subtitle: Text('Vehicle: $plate'),
            trailing: devOverride
                ? const Chip(
                    label: Text('DEV'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.amber,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => CrewService().signOut(),
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}
