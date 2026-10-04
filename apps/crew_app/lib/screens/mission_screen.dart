import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/crew_service.dart';

class MissionScreen extends StatefulWidget {
  const MissionScreen({super.key, required this.ambulanceId});

  final String ambulanceId;

  @override
  State<MissionScreen> createState() => _MissionScreenState();
}

class _MissionScreenState extends State<MissionScreen> {
  final _service = CrewService();
  List<Map<String, String>> _hospitals = [];

  @override
  void initState() {
    super.initState();
    _service.hospitals().then((h) {
      if (mounted) setState(() => _hospitals = h);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _service.watchMissionsFor(widget.ambulanceId),
      builder: (context, snapshot) {
        QueryDocumentSnapshot<Map<String, dynamic>>? active;
        for (final d in snapshot.data?.docs ?? []) {
          final s = d.data()['status'];
          if (s != null && activeStatuses.contains(s)) active = d;
        }
        if (active == null) {
          return const Center(
            child: Text('No active mission.\nWaiting for assignment…',
                textAlign: TextAlign.center),
          );
        }
        final data = active.data();
        final status = data['status'] as String;
        final patientId = data['patientId'] as String?;
        final hospitalId = data['hospitalId'] as String?;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.medical_services),
                title: Text(statusLabels[status] ?? status),
                subtitle: Text('Mission ${active.id.substring(0, 6)}'),
              ),
            ),
            _PatientCard(service: _service, patientId: patientId),
            if (status == 'assigned') _acceptRow(active.id),
            if (status == 'accepted')
              _action(active.id, 'Start (en route)', 'enRoute'),
            if (status == 'enRoute')
              _action(active.id, 'Arrived on scene', 'onScene'),
            if (status == 'onScene') ...[
              _hospitalPicker(active.id, hospitalId),
              _action(active.id, 'Start transport', 'transporting',
                  requiresHospital: hospitalId != null),
            ],
            if (status == 'transporting')
              _action(active.id, 'Arrived at hospital', 'atHospital'),
            if (status == 'atHospital')
              _action(active.id, 'Complete mission', 'resolved'),
          ],
        );
      },
    );
  }

  Widget _acceptRow(String missionId) {
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: () => _service.accept(missionId),
            child: const Text('Accept'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: () => _service.reject(missionId),
            child: const Text('Reject'),
          ),
        ),
      ],
    );
  }

  Widget _action(String missionId, String label, String next,
      {bool requiresHospital = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: requiresHospital
              ? null
              : () => _service.advance(missionId, next),
          child: Text(label),
        ),
      ),
    );
  }

  Widget _hospitalPicker(String missionId, String? selected) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DropdownButtonFormField<String>(
        initialValue:
            _hospitals.any((h) => h['id'] == selected) ? selected : null,
        decoration: const InputDecoration(labelText: 'Destination hospital'),
        items: _hospitals
            .map((h) => DropdownMenuItem(value: h['id'], child: Text(h['name']!)))
            .toList(),
        onChanged: (v) {
          if (v != null) _service.setHospital(missionId, v);
        },
      ),
    );
  }
}

class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.service, required this.patientId});

  final CrewService service;
  final String? patientId;

  @override
  Widget build(BuildContext context) {
    if (patientId == null) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.person),
          title: Text('Guest caller'),
          subtitle: Text('No medical profile shared'),
        ),
      );
    }
    return FutureBuilder<Map<String, dynamic>?>(
      future: service.patientProfile(patientId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(child: ListTile(title: Text('Loading patient…')));
        }
        final p = snapshot.data!;
        return Card(
          child: ListTile(
            leading: const Icon(Icons.person, color: Colors.red),
            title: Text('Patient: ${p['bloodType'] ?? '—'}'),
            subtitle: Text(
              'Allergies: ${p['allergies'] ?? '—'}\n'
              'Conditions: ${p['conditions'] ?? '—'}\n'
              'Contact: ${p['emergencyContact'] ?? '—'}',
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}
