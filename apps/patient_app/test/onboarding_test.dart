import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:patient_app/core/app_repository.dart';
import 'package:patient_app/core/app_state.dart';
import 'package:patient_app/screens/onboarding_screen.dart';

/// Timer-free repository so the demo ticker doesn't leak a pending timer into
/// the test binding (the onboarding screen only calls `completeOnboarding`).
class _FakeRepo extends ChangeNotifier implements AppRepository {
  @override
  List<AmbulanceUnit> get units => const [];
  @override
  List<Incident> get history => const [];
  @override
  Incident? get activeIncident => null;
  @override
  MedicalProfile get medicalProfile => MedicalProfile();
  @override
  LatLng get userLocation => const LatLng(0, 0);
  @override
  List<LatLng>? get activeRoute => null;
  @override
  bool get isAuthenticated => false;
  @override
  bool get offline => false;
  @override
  bool get fleetLoading => false;
  @override
  bool get fleetError => false;
  @override
  DateTime get lastFleetUpdate => DateTime(0);
  @override
  bool get medicalLoading => false;
  @override
  bool get sendFailed => false;
  @override
  LatLng? get lastRequestPickup => null;
  @override
  bool get lastRequestMedical => false;
  @override
  bool get simulateSubmitError => false;
  @override
  bool get simulateSaveError => false;
  @override
  void signIn() {}
  @override
  void signOut() {}
  @override
  void setUserLocation(LatLng point) {}
  @override
  void setOffline(bool value) {}
  @override
  void refreshFleet() {}
  @override
  void setFleetError(bool value) {}
  @override
  void triggerRequest(
      {LatLng? pickup,
      bool? medicalAttached,
      String? guestName,
      String? guestPhone}) {}
  @override
  void cancelRequest() {}
  @override
  void clearActiveIncident() {}
  @override
  bool setBloodType(String? value) => true;
  @override
  bool setAllergies(List<String> value) => true;
  @override
  bool setConditions(List<String> value) => true;
  @override
  bool addContact(EmergencyContact contact) => true;
  @override
  bool updateContact(EmergencyContact contact) => true;
  @override
  bool removeContact(EmergencyContact contact) => true;
  @override
  void resetMedicalProfile() {}
  @override
  void setSimulateSubmitError(bool value) {}
  @override
  void setSimulateSaveError(bool value) {}
}

void main() {
  Widget host(AppState state, {bool disableAnimations = false}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: OnboardingScreen(state: state),
        ),
      );

  testWidgets('Next advances through all 3 pages and Get started finishes',
      (tester) async {
    final state = AppState(repository: _FakeRepo());
    await tester.pumpWidget(host(state));

    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 3'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(state.onboardingDone, isTrue);
  });

  testWidgets('Skip finishes onboarding from the first page', (tester) async {
    final state = AppState(repository: _FakeRepo());
    await tester.pumpWidget(host(state));

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(state.onboardingDone, isTrue);
  });

  testWidgets('swiping a page also advances (drag still works)', (tester) async {
    final state = AppState(repository: _FakeRepo());
    await tester.pumpWidget(host(state));

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 800);
    await tester.pumpAndSettle();
    expect(find.text('2 of 3'), findsOneWidget);
  });

  testWidgets('Next advances when animations are disabled (zero duration)',
      (tester) async {
    final state = AppState(repository: _FakeRepo());
    await tester.pumpWidget(host(state, disableAnimations: true));

    expect(find.text('1 of 3'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3'), findsOneWidget);
  });
}
