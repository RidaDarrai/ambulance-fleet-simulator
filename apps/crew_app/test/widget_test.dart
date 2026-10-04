import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crew_app/screens/login_screen.dart';

void main() {
  testWidgets('renders crew login', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.text('Ambulance Crew'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
