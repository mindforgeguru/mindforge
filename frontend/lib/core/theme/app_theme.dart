import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'brand_palette.dart';

/// MIND FORGE color palette.
///
/// **Reactive theming** — the brand-tinted tokens (`primary`, `secondary`,
/// `accent`, and their light/dark variants + `iconContainer`) are runtime
/// getters that read from a swappable [BrandPalette]. Status colors,
/// surfaces, dividers, and text tones stay `const` so readability is
/// stable across themes.
///
/// To switch palettes call [applyPalette]; the [paletteVersion] notifier
/// fires so a [ValueListenableBuilder] near the [MaterialApp] root can
/// rebuild the tree with the new colors.
class AppColors {
  AppColors._();

  // ── Reactive backing store ─────────────────────────────────────────────────
  static BrandPalette _palette = BrandPalettes.mindForge;
  static BrandPalette get currentPalette => _palette;

  /// Bumped every time the palette swaps. Listeners (specifically a
  /// [ValueListenableBuilder] wrapping [MaterialApp]) rebuild the tree
  /// when this changes so every screen reads the new color values.
  static final ValueNotifier<int> paletteVersion = ValueNotifier<int>(0);

  static void applyPalette(BrandPalette palette) {
    if (palette.id == _palette.id) return;
    _palette = palette;
    paletteVersion.value++;
  }

  // ── Brand-tinted (vary per palette) ────────────────────────────────────────
  static Color get primary => _palette.primary;
  static Color get primaryLight => _palette.primaryLight;
  static Color get primaryDark => _palette.primaryDark;

  static Color get secondary => _palette.secondary;
  static Color get secondaryLight => _palette.secondaryLight;
  static Color get secondaryDark => _palette.secondaryDark;

  static Color get accent => _palette.accent;
  static Color get accentLight => _palette.accentLight;
  static Color get accentDark => _palette.accentDark;

  static Color get iconContainer => _palette.iconContainer;

  // ── Fixed neutrals & surfaces (const — don't vary by theme) ────────────────
  static const Color surface = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFEDF2F8);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFC5D3E0);

  // Status — kept stable so success/warning/error semantics never shift.
  static const Color success = Color(0xFF2E7D52);
  static const Color warning = Color(0xFFB07A20);
  static const Color error = Color(0xFFB03030);
  static const Color info = Color(0xFF457B9D);

  // Text — stable readability against white card backgrounds.
  static const Color textPrimary = Color(0xFF1D3557);
  static const Color textSecondary = Color(0xFF457B9D);
  static const Color textMuted = Color(0xFF8A9BAD);
  static const Color textOnDark = Color(0xFFFFFFFF);

  // Dark theme surfaces (rarely used today; kept for completeness).
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

    final colorScheme = ColorScheme(
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
      errorContainer: const Color(0xFFFFCDD2),
      onErrorContainer: AppColors.error,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.background,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.divider,
      shadow: const Color(0x1A1D3557),
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
          side: BorderSide(color: AppColors.primary, width: 1.5),
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
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 12),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.iconContainer,
        selectedColor: AppColors.primary,
        shape: const RoundedRectangleBorder(
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
      colorScheme: ColorScheme(
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
        error: const Color(0xFFEF9A9A),
        onError: AppColors.darkBackground,
        errorContainer: AppColors.error,
        onErrorContainer: const Color(0xFFFFCDD2),
        surface: AppColors.darkSurface,
        onSurface: AppColors.textOnDark,
        surfaceContainerHighest: AppColors.darkCard,
        onSurfaceVariant: AppColors.textMuted,
        outline: const Color(0xFF2A4060),
        shadow: const Color(0x40000000),
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
