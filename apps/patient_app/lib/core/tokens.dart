import 'package:flutter/material.dart';

/// Single source of truth for colors — mirrors `design-tokens.md` v1 exactly.
/// Never hardcode hex values in widgets; always reference these tokens.
abstract final class AppColors {
  // ── Brand palette ────────────────────────────────────────────────────
  static const Color primary = Color(0xFF0EA5E9); // sky 500
  static const Color primaryForeground = Color(0xFFFFFFFF);
  static const Color primaryHover = Color(0xFF0284C7); // sky 600
  static const Color background = Color(0xFFF8FAFC); // slate 50
  static const Color backgroundDark = Color(0xFF0F172A); // slate 900
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF1F5F9); // slate 100
  static const Color border = Color(0xFFE2E8F0); // slate 200
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textInverse = Color(0xFFF8FAFC);

  // ── Mission lifecycle status colors (light / dark) ──────────────────
  static const Color statusPending = Color(0xFFF59E0B); // amber 500
  static const Color statusPendingDark = Color(0xFFFBBF24); // amber 400
  static const Color statusDispatched = Color(0xFF3B82F6); // blue 500
  static const Color statusDispatchedDark = Color(0xFF60A5FA); // blue 400
  static const Color statusEnRoute = Color(0xFF06B6D4); // cyan 500
  static const Color statusEnRouteDark = Color(0xFF22D3EE); // cyan 400
  static const Color statusOnScene = Color(0xFF8B5CF6); // violet 500
  static const Color statusOnSceneDark = Color(0xFFA78BFA); // violet 400
  static const Color statusTransporting = Color(0xFFF97316); // orange 500
  static const Color statusTransportingDark = Color(0xFFFB923C); // orange 400
  static const Color statusAtHospital = Color(0xFF14B8A6); // teal 500
  static const Color statusAtHospitalDark = Color(0xFF2DD4BF); // teal 400
  static const Color statusResolved = Color(0xFF22C55E); // green 500
  static const Color statusResolvedDark = Color(0xFF4ADE80); // green 400

  // ── Danger / safety ─────────────────────────────────────────────────
  static const Color danger = Color(0xFFEF4444);
  static const Color dangerHover = Color(0xFFDC2626);
  static const Color dangerSurface = Color(0xFFFEF2F2); // red 50
  static const Color dangerBorder = Color(0xFFFECACA); // red 200

  // ── Medical ─────────────────────────────────────────────────────────
  static const Color medicalSurface = Color(0xFFEFF6FF); // blue 50
  static const Color medicalBorder = Color(0xFFDBEAFE); // blue 100

  // ── Dark-mode panels ────────────────────────────────────────────────
  static const Color panelDark = Color(0xFF1E293B); // slate 800
  static const Color borderDark = Color(0xFF334155); // slate 700

  // ── Geometry tokens ─────────────────────────────────────────────────
  static const double radiusSm = 6;
  static const double radiusMd = 10;
  static const double radiusLg = 16;
  static const double radiusFull = 9999;
  static const double panicSize = 72;
  static const double space4 = 16; // mobile horizontal padding
  static const double space6 = 24;
}