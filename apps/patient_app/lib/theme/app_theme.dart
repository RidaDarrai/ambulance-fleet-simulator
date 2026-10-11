import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/tokens.dart';

/// Typographic tokens from design-tokens.md §4.
abstract final class AppText {
  static const double displaySize = 32;
  static const double h1Size = 24;
  static const double h2Size = 18;
  static const double h3Size = 16;
  static const double bodySize = 14;
  static const double bodySmallSize = 13;
  static const double labelSize = 12;
}

/// ETA style — mono, bold, tabular digits (never jitter). Token `type.display.mono`.
TextStyle etaDisplayStyle({double size = AppText.displaySize, Color? color}) =>
    GoogleFonts.jetBrainsMono(
      fontSize: size,
      height: 1.25,
      fontWeight: FontWeight.w700,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

ThemeData buildAppTheme({required Brightness brightness}) {
  final isDark = brightness == Brightness.dark;
  final bg = isDark ? AppColors.backgroundDark : AppColors.background;
  final surface = isDark ? AppColors.panelDark : AppColors.surface;
  final onSurface = isDark ? AppColors.textInverse : AppColors.textPrimary;
  final onSurfaceSecondary =
      isDark ? AppColors.textMuted : AppColors.textSecondary;
  final border = isDark ? AppColors.borderDark : AppColors.border;

  final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary)
      .copyWith(
        brightness: brightness,
        primary: AppColors.primary,
        onPrimary: AppColors.primaryForeground,
        secondary: isDark ? AppColors.statusEnRouteDark : AppColors.statusEnRoute,
        error: AppColors.danger,
        onError: Colors.white,
        surface: surface,
        onSurface: onSurface,
        outline: border,
        outlineVariant: border,
      );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
    dividerColor: border,
    fontFamily: 'Inter',
  );

  final text = GoogleFonts.interTextTheme(base.textTheme).copyWith(
    displayLarge: GoogleFonts.inter(
        fontSize: AppText.displaySize, height: 1.25, fontWeight: FontWeight.w700, color: onSurface),
    headlineLarge: GoogleFonts.inter(
        fontSize: AppText.h1Size, height: 32 / AppText.h1Size, fontWeight: FontWeight.w700, color: onSurface),
    headlineMedium: GoogleFonts.inter(
        fontSize: AppText.h2Size, height: 28 / AppText.h2Size, fontWeight: FontWeight.w600, color: onSurface),
    headlineSmall: GoogleFonts.inter(
        fontSize: AppText.h3Size, height: 24 / AppText.h3Size, fontWeight: FontWeight.w600, color: onSurface),
    bodyLarge: GoogleFonts.inter(
        fontSize: AppText.bodySize, height: 22 / AppText.bodySize, fontWeight: FontWeight.w400, color: onSurface),
    bodyMedium: GoogleFonts.inter(
        fontSize: AppText.bodySize, height: 22 / AppText.bodySize, fontWeight: FontWeight.w400, color: onSurface),
    bodySmall: GoogleFonts.inter(
        fontSize: AppText.bodySmallSize,
        height: 20 / AppText.bodySmallSize,
        fontWeight: FontWeight.w400,
        color: onSurfaceSecondary),
    labelLarge: GoogleFonts.inter(
        fontSize: AppText.labelSize, height: 16 / AppText.labelSize, fontWeight: FontWeight.w600, color: onSurface),
    labelSmall: GoogleFonts.inter(
        fontSize: AppText.labelSize - 1,
        height: 14 / (AppText.labelSize - 1),
        fontWeight: FontWeight.w600,
        letterSpacing: 0.08,
        color: onSurfaceSecondary),
  );

  return base.copyWith(
    textTheme: text,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? surface : AppColors.textPrimary,
      contentTextStyle: GoogleFonts.inter(
          fontSize: AppText.bodySize, color: isDark ? onSurface : Colors.white),
      actionTextColor: AppColors.primaryHover,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      showDragHandle: true,
      modalBackgroundColor: surface,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: AppColors.primary.withValues(alpha: 0.14),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(GoogleFonts.inter(
          fontSize: AppText.labelSize, fontWeight: FontWeight.w600, color: onSurfaceSecondary)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: onSurface,
      elevation: 0,
      centerTitle: false,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.primaryForeground,
    ),
  );
}

ThemeData buildLightTheme() => buildAppTheme(brightness: Brightness.light);
ThemeData buildDarkTheme() => buildAppTheme(brightness: Brightness.dark);