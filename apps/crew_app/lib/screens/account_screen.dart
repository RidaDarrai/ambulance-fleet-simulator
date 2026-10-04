import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/crew_service.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    required this.user,
    required this.ambulanceId,
    required this.plate,
  });

  final User user;
  final String ambulanceId;
  final String plate;

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
