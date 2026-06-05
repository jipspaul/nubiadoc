// lib/theme/nubia_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'nubia_colors.dart';
import 'nubia_tokens.dart';

/// Fabrique des thèmes Material 3 Nubia (clair + sombre).
///
/// Traduit les tokens (`design/03-design-system/01-tokens.md` §1.5) en
/// `ThemeData` : `colorScheme` sur la palette de marque, typographie `Inter`
/// (et `Fraunces` pour le seul token `display`) via `google_fonts`, et les
/// rôles sémantiques Nubia branchés en [ThemeExtension] ([NubiaTokens]).
///
/// Référence : `design/03-design-system/03-flutter-theme.md` §3-§4 et
/// `design/07-handoff/00-fondations.md` §3 (typographie exacte).
class NubiaTheme {
  const NubiaTheme._();

  /// Thème clair Material 3 (primaire `brand/700`).
  static ThemeData get light => _build(_lightScheme, NubiaTokens.light);

  /// Thème sombre Material 3 (primaire `brand/400`).
  static ThemeData get dark => _build(_darkScheme, NubiaTokens.dark);

  static const ColorScheme _lightScheme = ColorScheme.light(
    primary: NubiaColors.brand700,
    onPrimary: NubiaColors.n0,
    primaryContainer: NubiaColors.brand50,
    onPrimaryContainer: NubiaColors.brand800,
    secondary: NubiaColors.brand600,
    onSecondary: NubiaColors.n0,
    surface: NubiaColors.n0,
    onSurface: NubiaColors.n900,
    onSurfaceVariant: NubiaColors.n600,
    error: NubiaColors.dangerFg,
    onError: NubiaColors.n0,
    outline: NubiaColors.n300,
  );

  static const ColorScheme _darkScheme = ColorScheme.dark(
    primary: NubiaColors.brand400,
    onPrimary: Color(0xFF052E22),
    primaryContainer: Color(0xFF0B3D2E),
    onPrimaryContainer: NubiaColors.brand200,
    secondary: NubiaColors.brand400,
    onSecondary: Color(0xFF052E22),
    surface: NubiaColors.n800,
    onSurface: NubiaColors.n50,
    onSurfaceVariant: NubiaColors.n300,
    error: Color(0xFFF87171),
    onError: Color(0xFF2A1212),
    outline: NubiaColors.n600,
  );

  static ThemeData _build(ColorScheme scheme, NubiaTokens tokens) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: _textTheme(scheme),
      extensions: [tokens],
    );
  }

  /// Échelle typographique Nubia (`00-fondations.md` §3) mappée sur les slots
  /// Material 3. Base `Inter` ; `display` en `Fraunces` (titres premium).
  static TextTheme _textTheme(ColorScheme scheme) {
    final Color onSurface = scheme.onSurface;
    return GoogleFonts.interTextTheme()
        .apply(bodyColor: onSurface, displayColor: onSurface)
        .copyWith(
          // display — Fraunces, seul token serif premium.
          displayLarge: GoogleFonts.fraunces(
            fontSize: 32,
            height: 40 / 32,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
            color: onSurface,
          ),
          // h1
          headlineLarge: GoogleFonts.inter(
            fontSize: 28,
            height: 36 / 28,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: onSurface,
          ),
          // h2
          headlineMedium: GoogleFonts.inter(
            fontSize: 24,
            height: 32 / 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: onSurface,
          ),
          // h3
          headlineSmall: GoogleFonts.inter(
            fontSize: 20,
            height: 28 / 20,
            fontWeight: FontWeight.w600,
            color: onSurface,
          ),
          // title
          titleLarge: GoogleFonts.inter(
            fontSize: 18,
            height: 26 / 18,
            fontWeight: FontWeight.w500,
            color: onSurface,
          ),
          // body
          bodyMedium: GoogleFonts.inter(
            fontSize: 14,
            height: 22 / 14,
            fontWeight: FontWeight.w400,
            color: onSurface,
          ),
          // label (libellés + boutons)
          labelLarge: GoogleFonts.inter(
            fontSize: 14,
            height: 20 / 14,
            fontWeight: FontWeight.w500,
            color: onSurface,
          ),
          // caption
          bodySmall: GoogleFonts.inter(
            fontSize: 13,
            height: 18 / 13,
            fontWeight: FontWeight.w400,
            color: onSurface,
          ),
          // micro
          labelSmall: GoogleFonts.inter(
            fontSize: 12,
            height: 16 / 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
            color: onSurface,
          ),
        );
  }
}
