/// Responsive sizing utility — Flutter equivalents of CSS responsive units.
///
/// | CSS                     | Flutter (this class)                   |
/// |-------------------------|----------------------------------------|
/// | vw / vh                 | R.vw() / R.vh()                        |
/// | clamp(min, pref, max)   | R.fluid()                              |
/// | rem / em font scaling   | R.fs()                                 |
/// | @media (max-width: Xpx) | R.isSmall / isMedium / isLarge         |
/// | Flexbox gap / padding   | R.sp()                                 |
library;

import 'package:flutter/widgets.dart';

class R {
  R._();

  /// Design reference width (iPhone 14 base — 390 logical px).
  /// All [fluid] sizes are expressed relative to this width.
  static const double _base = 390.0;

  // ── Viewport units ────────────────────────────────────────────────────────

  /// CSS `Xvw` — X percent of the viewport width.
  static double vw(BuildContext context, double percent) =>
      MediaQuery.sizeOf(context).width * percent / 100;

  /// CSS `Xvh` — X percent of the viewport height.
  static double vh(BuildContext context, double percent) =>
      MediaQuery.sizeOf(context).height * percent / 100;

  // ── Fluid sizing (CSS clamp) ──────────────────────────────────────────────

  /// CSS `clamp(min, preferred, max)`.
  ///
  /// [preferred] is the size at the 390-px base width.
  /// It scales linearly with screen width, then gets clamped.
  static double fluid(
    BuildContext context,
    double preferred, {
    required double min,
    required double max,
  }) {
    final scale = MediaQuery.sizeOf(context).width / _base;
    return (preferred * scale).clamp(min, max);
  }

  // ── Font sizes (CSS rem / em) ─────────────────────────────────────────────

  /// Fluid font size. Scales with screen width, clamped ±20 % by default.
  static double fs(
    BuildContext context,
    double size, {
    double? min,
    double? max,
  }) =>
      fluid(
        context,
        size,
        min: min ?? (size * 0.80),
        max: max ?? (size * 1.20),
      );

  // ── Spacing (CSS gap / padding / margin) ─────────────────────────────────

  /// Fluid spacing. Scales with screen width, clamped ±25 % by default.
  static double sp(
    BuildContext context,
    double size, {
    double? min,
    double? max,
  }) =>
      fluid(
        context,
        size,
        min: min ?? (size * 0.75),
        max: max ?? (size * 1.25),
      );

  // ── Breakpoints (CSS @media) ──────────────────────────────────────────────

  /// Small phones: iPhone SE, Galaxy A03 — width < 360 px.
  static bool isSmall(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 360;

  /// Medium phones: most Android & iPhones — 360–429 px.
  static bool isMedium(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= 360 && w < 430;
  }

  /// Large phones / small tablets: Pixel 7 Pro, iPhone 15 Pro Max — ≥ 430 px.
  static bool isLarge(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 430;

  // ── Convenience getters ───────────────────────────────────────────────────

  static double screenWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static double screenHeight(BuildContext context) =>
      MediaQuery.sizeOf(context).height;
}
