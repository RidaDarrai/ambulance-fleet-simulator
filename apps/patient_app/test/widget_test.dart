import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:patient_app/core/mission_status.dart';
import 'package:patient_app/core/tokens.dart';

void main() {
  test('tokens: brand palette pinned from design-tokens.md v1', () {
    expect(AppColors.primary, const Color(0xFF0EA5E9)); // sky 500
    expect(AppColors.backgroundDark, const Color(0xFF0F172A));
    expect(AppColors.danger, const Color(0xFFEF4444));
  });

  test('lifecycle: exactly the 7 locked statuses, ordered', () {
    expect(
      MissionStatus.values.map((s) => s.name).toList(),
      [
        'pending',
        'dispatched',
        'enRoute',
        'onScene',
        'transporting',
        'atHospital',
        'resolved',
      ],
    );
  });

  test('lifecycle: every status has a distinct light color token', () {
    final colors = MissionStatus.values.map((s) => s.light().toARGB32()).toSet();
    expect(colors.length, MissionStatus.values.length);
  });
}