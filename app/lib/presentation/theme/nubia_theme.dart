// lib/presentation/theme/nubia_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:nubia_patient/presentation/theme/nubia_colors.dart';
import 'package:nubia_patient/presentation/theme/nubia_tokens.dart';

/// Fabrique des thèmes Material 3 Nubia (clair + sombre).
///
/// Traduit les tokens (`design/03-design-system/01-tokens.md` §1.5) en
/// [ThemeData] : `colorScheme` issu de la palette ([NubiaColors]), typographie
/// `Inter` via `google_fonts` — `Fraunces` réservé au seul token `display`
/// (grand titre premium) — et rôles sémantiques Nubia branchés via l'extension
/// [NubiaTokens].
///
/// Réfs : `design/03-design-system/03-flutter-theme.md` §3 et §4 ;
/// `design/07-handoff/00-fondations.md` §3 (typographie exacte).
class NubiaTheme {
  /// Thème clair — primaire `brand/700`.
  static ThemeData get light => _build(_lightScheme, NubiaTokens.light);

  /// Thème sombre — primaire `brand/400`.
  static ThemeData get dark => _build(_darkScheme, NubiaTokens.dark);

  /// ColorScheme clair (`01-tokens.md` §1.5 colonne « Clair »).
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

  /// ColorScheme sombre (`01-tokens.md` §1.5 colonne « Sombre »).
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
      // `bg/page` (§1.5) : neutre chaud distinct de la surface des cartes.
      scaffoldBackgroundColor: scheme.brightness == Brightness.light
          ? NubiaColors.n50
          : NubiaColors.n900,
      textTheme: _textTheme(scheme),
      extensions: [tokens],
    );
  }

  /// Échelle typographique Nubia (`00-fondations.md` §3) mappée sur les rôles
  /// Material 3. Tout est `Inter` sauf `display` en `Fraunces`.
  static TextTheme _textTheme(ColorScheme scheme) {
    final base = GoogleFonts.interTextTheme().apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    return base.copyWith(
      // display — seule occurrence de Fraunces (grand titre premium)
      displayLarge: GoogleFonts.fraunces(
        fontSize: 32,
        height: 40 / 32,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        color: scheme.onSurface,
      ),
      // h1 → h3
      headlineLarge: GoogleFonts.inter(
        fontSize: 28,
        height: 36 / 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: scheme.onSurface,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 24,
        height: 32 / 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: scheme.onSurface,
      ),
      headlineSmall: GoogleFonts.inter(
        fontSize: 20,
        height: 28 / 20,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      // title (titre de carte)
      titleLarge: GoogleFonts.inter(
        fontSize: 18,
        height: 26 / 18,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      // body-lg (corps mobile)
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        height: 26 / 16,
        fontWeight: FontWeight.w400,
        color: scheme.onSurface,
      ),
      // body (corps / back-office)
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        height: 22 / 14,
        fontWeight: FontWeight.w400,
        color: scheme.onSurface,
      ),
      // label (libellés, boutons)
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      // caption (aides, métadonnées)
      bodySmall: GoogleFonts.inter(
        fontSize: 13,
        height: 18 / 13,
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
      ),
      // micro (badges, tags)
      labelSmall: GoogleFonts.inter(
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
