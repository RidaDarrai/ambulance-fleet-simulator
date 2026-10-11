import 'package:flutter_test/flutter_test.dart';

import 'package:patient_app/core/app_state.dart';
import 'package:patient_app/core/demo_repository.dart';
import 'package:patient_app/core/mission_status.dart';

void main() {
  group('AppState ↔ repository seam', () {
    test('defaults to the DemoRepository so UI works without a backend', () {
      final state = AppState();
      addTearDown(state.dispose);

      expect(state.isDemo, isTrue);
      expect(state.units, hasLength(3)); // seeded fleet
      expect(state.medicalProfile.bloodType, 'O+'); // seeded profile
      expect(state.activeIncident, isNull);
    });

    test('triggerRequest creates a pending incident via the repository', () {
      final state = AppState();
      addTearDown(state.dispose);

      state.triggerRequest();
      final inc = state.activeIncident;

      expect(inc, isNotNull);
      expect(inc!.status, MissionStatus.pending);
      expect(inc.queuePosition, 2);
      expect(inc.medicalAttached, isFalse);
    });

    test('a second request while one is active is ignored', () {
      final state = AppState();
      addTearDown(state.dispose);

      state.triggerRequest();
      final firstId = state.activeIncident!.id;
      state.triggerRequest();

      expect(state.activeIncident!.id, firstId);
    });

    test('medical edits flow through the repository and refresh lastUpdated',
        () {
      final state = AppState();
      addTearDown(state.dispose);
      final before = state.medicalProfile.lastUpdated;

      final ok = state.setBloodType('A-');

      expect(ok, isTrue);
      expect(state.medicalProfile.bloodType, 'A-');
      expect(
          state.medicalProfile.lastUpdated.isBefore(before), isFalse);
    });

    test('signOut toggles auth through the repository', () {
      final state = AppState();
      addTearDown(state.dispose);

      state.signIn();
      expect(state.isAuthenticated, isTrue);
      state.signOut();
      expect(state.isAuthenticated, isFalse);
    });

    test('useRepository swaps the data source and notifies', () {
      final state = AppState();
      addTearDown(state.dispose);
      var notified = false;
      state.addListener(() => notified = true);

      state.useRepository(DemoRepository());

      expect(notified, isTrue);
      expect(state.isDemo, isTrue);
    });
  });

  group('backend status → design status (8 → 7 fold)', () {
    test('the 8 backend statuses all land on one of the locked 7', () {
      const backend = [
        'requested',
        'assigned',
        'accepted',
        'enRoute',
        'onScene',
        'transporting',
        'atHospital',
        'resolved',
      ];
      final mapped = backend.map(mapBackendStatus).toSet();

      // All results are valid design statuses…
      expect(mapped.every((s) => MissionStatus.values.contains(s)), isTrue);
      // …and the two dispatch-phase backend states collapse to one.
      expect(mapBackendStatus('assigned'), MissionStatus.dispatched);
      expect(mapBackendStatus('accepted'), MissionStatus.dispatched);
      expect(mapBackendStatus('requested'), MissionStatus.pending);
      // 8 backend → 7 design (assigned + accepted share `dispatched`).
      expect(mapped.length, 7);
    });

    test('unknown status degrades to pending instead of throwing', () {
      expect(mapBackendStatus('weird-new-state'), MissionStatus.pending);
      expect(mapBackendStatus(''), MissionStatus.pending);
    });
  });
}
