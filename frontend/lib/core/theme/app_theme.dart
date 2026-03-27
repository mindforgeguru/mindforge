import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// MIND FORGE v2 color palette — deep navy, white, coral orange.
class AppColors {
  AppColors._();

  // Primary — deep navy #1D3557
  static const Color primary = Color(0xFF1D3557);
  static const Color primaryLight = Color(0xFF2E4F7A);
  static const Color primaryDark = Color(0xFF0F1F35);

  // Secondary — slate blue (complements navy)
  static const Color secondary = Color(0xFF457B9D);
  static const Color secondaryLight = Color(0xFF6FA3C0);
  static const Color secondaryDark = Color(0xFF2C5F7A);

  // Accent — coral orange #D4653B
  static const Color accent = Color(0xFFD4653B);
  static const Color accentLight = Color(0xFFE8895F);
  static const Color accentDark = Color(0xFFAA4A27);

  // Neutral / surfaces
  static const Color surface = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFEDF2F8);   // light blue-gray
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color iconContainer = Color(0xFFDCE8F5); // light blue for icon bg
  static const Color divider = Color(0xFFC5D3E0);

  // Status
  static const Color success = Color(0xFF2E7D52);
  static const Color warning = Color(0xFFB07A20);
  static const Color error = Color(0xFFB03030);
  static const Color info = Color(0xFF457B9D);

  // Text
  static const Color textPrimary = Color(0xFF1D3557);   // deep navy
  static const Color textSecondary = Color(0xFF457B9D); // slate blue
  static const Color textMuted = Color(0xFF8A9BAD);     // blue-gray
  static const Color textOnDark = Color(0xFFFFFFFF);    // white on dark

  // Dark theme surfaces
  static const Color darkBackground = Color(0xFF0F1F35);
  static const Color darkSurface = Color(0xFF1A2E4A);
  static const Color darkCard = Color(0xFF1F3855);
}

class AppTheme {
  AppTheme._();

  static TextTheme _buildTextTheme() {
    final base = GoogleFonts.poppinsTextTheme();
    return base.copyWith(
      displayLarge:  base.displayLarge?.copyWith(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      displayMedium: base.displayMedium?.copyWith(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      headlineLarge: base.headlineLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      headlineMedium:base.headlineMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      headlineSmall: base.headlineSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      titleLarge:    base.titleLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      titleMedium:   base.titleMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      bodyLarge:     base.bodyLarge?.copyWith(fontSize: 14, color: AppColors.textPrimary),
      bodyMedium:    base.bodyMedium?.copyWith(fontSize: 12, color: AppColors.textSecondary),
      bodySmall:     base.bodySmall?.copyWith(fontSize: 11, color: AppColors.textMuted),
      labelLarge:    base.labelLarge?.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
    );
  }

  static ThemeData get lightTheme {
    final textTheme = _buildTextTheme();

    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: AppColors.textOnDark,
      primaryContainer: AppColors.primaryLight,
      onPrimaryContainer: AppColors.textOnDark,
      secondary: AppColors.secondary,
      onSecondary: AppColors.textOnDark,
      secondaryContainer: AppColors.secondaryLight,
      onSecondaryContainer: AppColors.textOnDark,
      tertiary: AppColors.accent,
      onTertiary: AppColors.textOnDark,
      tertiaryContainer: AppColors.accentLight,
      onTertiaryContainer: AppColors.textPrimary,
      error: AppColors.error,
      onError: AppColors.textOnDark,
      errorContainer: Color(0xFFFFCDD2),
      onErrorContainer: AppColors.error,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.background,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.divider,
      shadow: Color(0x1A1D3557),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: AppColors.background,
      cardTheme: const CardThemeData(
        color: AppColors.cardBackground,
        elevation: 2,
        shadowColor: Color(0x151D3557),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.poppins(
          color: AppColors.textOnDark,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnDark,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.poppins(fontSize: 13),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 12),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: AppColors.iconContainer,
        selectedColor: AppColors.primary,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8))),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        space: 1,
        thickness: 1,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textMuted,
        indicatorColor: AppColors.primary,
        labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle: GoogleFonts.poppins(fontSize: 11),
      ),
    );
  }

  static ThemeData get darkTheme {
    return lightTheme.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkBackground,
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: AppColors.primaryLight,
        onPrimary: AppColors.textOnDark,
        primaryContainer: AppColors.primaryDark,
        onPrimaryContainer: AppColors.textOnDark,
        secondary: AppColors.secondaryLight,
        onSecondary: AppColors.textOnDark,
        secondaryContainer: AppColors.secondaryDark,
        onSecondaryContainer: AppColors.textOnDark,
        tertiary: AppColors.accentLight,
        onTertiary: AppColors.textOnDark,
        tertiaryContainer: AppColors.accentDark,
        onTertiaryContainer: AppColors.textOnDark,
        error: Color(0xFFEF9A9A),
        onError: AppColors.darkBackground,
        errorContainer: AppColors.error,
        onErrorContainer: Color(0xFFFFCDD2),
        surface: AppColors.darkSurface,
        onSurface: AppColors.textOnDark,
        surfaceContainerHighest: AppColors.darkCard,
        onSurfaceVariant: AppColors.textMuted,
        outline: Color(0xFF2A4060),
        shadow: Color(0x40000000),
      ),
    );
  }
}

/// Shared card decoration used across the app.
BoxDecoration mindForgeCardDecoration({Color? color, double radius = 16}) {
  return BoxDecoration(
    color: color ?? AppColors.cardBackground,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: const [
      BoxShadow(
        color: Color(0x121D3557),
        blurRadius: 14,
        offset: Offset(0, 4),
      ),
    ],
  );
}
