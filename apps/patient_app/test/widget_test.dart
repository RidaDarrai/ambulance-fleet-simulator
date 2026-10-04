import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patient_app/main.dart';

void main() {
  testWidgets('renders navigation shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: HomeShell(tabs: [SizedBox(), SizedBox(), SizedBox()]),
    ));
    expect(find.text('Fleet Map'), findsOneWidget);
    expect(find.text('Emergency'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });
}
