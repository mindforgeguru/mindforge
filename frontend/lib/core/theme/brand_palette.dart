import 'package:flutter/material.dart';

/// Cosmetic palette swappable by the XP theme-unlock system.
///
/// Only the brand-tinted tokens (primary/secondary/accent + iconContainer)
/// vary between themes. Status colors (success/warning/error), surfaces
/// (background/card/divider), and text tones are intentionally fixed in
/// `AppColors` so the rest of the app stays readable.
///
/// The frontend is the source of truth for palette values. The backend
/// only stores theme ids (`tide_breeze`, `forest_path`, …) on
/// `student_xp.selected_theme` — it does not serialize colors over the
/// wire. New themes added here must also be declared in
/// `level_configs.unlocks` server-side.
@immutable
class BrandPalette {
  final String id;
  final String name;
  final String description;

  final Color primary;
  final Color primaryLight;
  final Color primaryDark;

  final Color secondary;
  final Color secondaryLight;
  final Color secondaryDark;

  final Color accent;
  final Color accentLight;
  final Color accentDark;

  final Color iconContainer;

  const BrandPalette({
    required this.id,
    required this.name,
    required this.description,
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.secondary,
    required this.secondaryLight,
    required this.secondaryDark,
    required this.accent,
    required this.accentLight,
    required this.accentDark,
    required this.iconContainer,
  });
}

/// Catalogue of every theme. Order matters: lowest unlock_level first so
/// the picker reads naturally top-to-bottom.
class BrandPalettes {
  BrandPalettes._();

  // ── Default — always unlocked at level 1 ───────────────────────────────────
  static const mindForge = BrandPalette(
    id: 'mind_forge',
    name: 'Mind Forge',
    description: 'The classic navy & coral.',
    primary: Color(0xFF1D3557),
    primaryLight: Color(0xFF2E4F7A),
    primaryDark: Color(0xFF0F1F35),
    secondary: Color(0xFF457B9D),
    secondaryLight: Color(0xFF6FA3C0),
    secondaryDark: Color(0xFF2C5F7A),
    accent: Color(0xFFD4653B),
    accentLight: Color(0xFFE8895F),
    accentDark: Color(0xFFAA4A27),
    iconContainer: Color(0xFFDCE8F5),
  );

  // ── Tier 1 — Tide Breeze (L5) ──────────────────────────────────────────────
  // Cyan family — distinct from Forest Path's green and Mind Forge's navy.
  static const tideBreeze = BrandPalette(
    id: 'tide_breeze',
    name: 'Tide Breeze',
    description: 'Ocean cyan with a sunny yellow pop.',
    primary: Color(0xFF0E7490),       // cyan-700
    primaryLight: Color(0xFF06B6D4),  // cyan-500
    primaryDark: Color(0xFF155E75),   // cyan-800
    secondary: Color(0xFF22D3EE),     // cyan-400
    secondaryLight: Color(0xFF67E8F9),// cyan-300
    secondaryDark: Color(0xFF0891B2), // cyan-600
    accent: Color(0xFFFACC15),        // yellow-400
    accentLight: Color(0xFFFDE047),   // yellow-300
    accentDark: Color(0xFFCA8A04),    // yellow-600
    iconContainer: Color(0xFFCFFAFE), // cyan-100
  );

  // ── Tier 2 — Forest Path (L15) ─────────────────────────────────────────────
  // Green family — owns the natural / earthy slot in the palette ladder.
  static const forestPath = BrandPalette(
    id: 'forest_path',
    name: 'Forest Path',
    description: 'Vivid forest green with golden amber.',
    primary: Color(0xFF166534),       // green-800
    primaryLight: Color(0xFF16A34A),  // green-600
    primaryDark: Color(0xFF14532D),   // green-900
    secondary: Color(0xFF65A30D),     // lime-600
    secondaryLight: Color(0xFF84CC16),// lime-500
    secondaryDark: Color(0xFF4D7C0F), // lime-700
    accent: Color(0xFFF59E0B),        // amber-500
    accentLight: Color(0xFFFCD34D),   // amber-300
    accentDark: Color(0xFFB45309),    // amber-700
    iconContainer: Color(0xFFDCFCE7), // green-100
  );

  // ── Tier 3 — Royal Velvet (L30) ────────────────────────────────────────────
  static const royalVelvet = BrandPalette(
    id: 'royal_velvet',
    name: 'Royal Velvet',
    description: 'Deep purple, saffron gold.',
    primary: Color(0xFF2D1B69),
    primaryLight: Color(0xFF4A2E89),
    primaryDark: Color(0xFF1A0E45),
    secondary: Color(0xFF7B2CBF),
    secondaryLight: Color(0xFF9D4EDD),
    secondaryDark: Color(0xFF5A1F8A),
    accent: Color(0xFFF4C430),
    accentLight: Color(0xFFF8D766),
    accentDark: Color(0xFFC49B1F),
    iconContainer: Color(0xFFE2D4F0),
  );

  // ── Tier 4 — Mythic Aurora (L50) ───────────────────────────────────────────
  // Crimson family — fiery endgame palette. Distinct from purple of Royal
  // Velvet and the cool families of the lower tiers.
  static const mythicAurora = BrandPalette(
    id: 'mythic_aurora',
    name: 'Mythic Aurora',
    description: 'Crimson dawn with golden flame.',
    primary: Color(0xFF991B1B),       // red-800
    primaryLight: Color(0xFFDC2626),  // red-600
    primaryDark: Color(0xFF7F1D1D),   // red-900
    secondary: Color(0xFFEF4444),     // red-500
    secondaryLight: Color(0xFFFCA5A5),// red-300
    secondaryDark: Color(0xFFB91C1C), // red-700
    accent: Color(0xFFFBBF24),        // amber-400 (golden)
    accentLight: Color(0xFFFCD34D),   // amber-300
    accentDark: Color(0xFFD97706),    // amber-600
    iconContainer: Color(0xFFFEE2E2), // red-100
  );

  /// All palettes in display order. The first entry is the default.
  static const List<BrandPalette> all = [
    mindForge,
    tideBreeze,
    forestPath,
    royalVelvet,
    mythicAurora,
  ];

  static const Map<String, BrandPalette> _byId = {
    'mind_forge': mindForge,
    'tide_breeze': tideBreeze,
    'forest_path': forestPath,
    'royal_velvet': royalVelvet,
    'mythic_aurora': mythicAurora,
  };

  /// Resolve a theme id to its palette. Falls back to `mindForge` for
  /// unknown ids — keeps older clients functional if the backend later
  /// adds a theme this app doesn't know about.
  static BrandPalette byId(String? id) =>
      _byId[id] ?? mindForge;
}
