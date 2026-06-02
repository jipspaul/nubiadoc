# Thème Flutter — Nubia

> Traduction des tokens (`01-tokens.md`) en thème Flutter (Material 3, clair + sombre). À placer dans `app/lib/theme/` (et partagé avec le back-office). Police via `google_fonts` (`Inter` UI, `Fraunces` display).
>
> Principe : le `ColorScheme` Material couvre les rôles standards ; les rôles spécifiques Nubia (texte tertiaire, bordures, succès/warning/info, primary-subtle, sable) vivent dans une **`ThemeExtension` `NubiaTokens`**. Les widgets lisent `Theme.of(context).extension<NubiaTokens>()`.

## 1. Palette brute
```dart
// lib/theme/nubia_colors.dart
import 'dart:ui';

class NubiaColors {
  // Marque — émeraude
  static const brand50  = Color(0xFFECFDF5);
  static const brand100 = Color(0xFFD1FAE5);
  static const brand200 = Color(0xFFA7F3D0);
  static const brand300 = Color(0xFF6EE7B7);
  static const brand400 = Color(0xFF34D399);
  static const brand500 = Color(0xFF10B981);
  static const brand600 = Color(0xFF059669); // identité
  static const brand700 = Color(0xFF047857); // primaire clair
  static const brand800 = Color(0xFF065F46);
  static const brand900 = Color(0xFF064E3B);

  // Neutres chauds (stone)
  static const n0   = Color(0xFFFFFFFF);
  static const n50  = Color(0xFFFAFAF9);
  static const n100 = Color(0xFFF5F5F4);
  static const n200 = Color(0xFFE7E5E4);
  static const n300 = Color(0xFFD6D3D1);
  static const n400 = Color(0xFFA8A29E);
  static const n500 = Color(0xFF78716C);
  static const n600 = Color(0xFF57534E);
  static const n700 = Color(0xFF44403C);
  static const n800 = Color(0xFF292524);
  static const n900 = Color(0xFF1C1917);

  // Accent premium (sable) — rare
  static const sand100 = Color(0xFFF3EAD7);
  static const sand500 = Color(0xFFB0894F);
  static const sand700 = Color(0xFF876435);

  // Sémantiques (fg/bg clair puis sombre)
  static const successFg = Color(0xFF15803D);
  static const successBg = Color(0xFFDCFCE7);
  static const warningFg = Color(0xFFB45309);
  static const warningBg = Color(0xFFFEF3C7);
  static const dangerFg  = Color(0xFFB91C1C);
  static const dangerBg  = Color(0xFFFEE2E2);
  static const infoFg    = Color(0xFF0E7490);
  static const infoBg    = Color(0xFFCFFAFE);
}
```

## 2. ThemeExtension — rôles Nubia
```dart
// lib/theme/nubia_tokens.dart
import 'package:flutter/material.dart';
import 'nubia_colors.dart';

@immutable
class NubiaTokens extends ThemeExtension<NubiaTokens> {
  final Color textTertiary;
  final Color borderSubtle;
  final Color borderDefault;
  final Color primarySubtleBg;
  final Color primarySubtleFg;
  final Color successFg, successBg;
  final Color warningFg, warningBg;
  final Color dangerFg, dangerBg;
  final Color infoFg, infoBg;
  final Color accent; // sable

  const NubiaTokens({
    required this.textTertiary,
    required this.borderSubtle,
    required this.borderDefault,
    required this.primarySubtleBg,
    required this.primarySubtleFg,
    required this.successFg, required this.successBg,
    required this.warningFg, required this.warningBg,
    required this.dangerFg, required this.dangerBg,
    required this.infoFg, required this.infoBg,
    required this.accent,
  });

  static const light = NubiaTokens(
    textTertiary: NubiaColors.n400,
    borderSubtle: NubiaColors.n200,
    borderDefault: NubiaColors.n300,
    primarySubtleBg: NubiaColors.brand50,
    primarySubtleFg: NubiaColors.brand800,
    successFg: NubiaColors.successFg, successBg: NubiaColors.successBg,
    warningFg: NubiaColors.warningFg, warningBg: NubiaColors.warningBg,
    dangerFg: NubiaColors.dangerFg, dangerBg: NubiaColors.dangerBg,
    infoFg: NubiaColors.infoFg, infoBg: NubiaColors.infoBg,
    accent: NubiaColors.sand500,
  );

  static const dark = NubiaTokens(
    textTertiary: NubiaColors.n400,
    borderSubtle: NubiaColors.n700,
    borderDefault: NubiaColors.n600,
    primarySubtleBg: Color(0xFF0B3D2E),
    primarySubtleFg: NubiaColors.brand200,
    successFg: Color(0xFF4ADE80), successBg: Color(0xFF14271A),
    warningFg: Color(0xFFFBBF24), warningBg: Color(0xFF2A1E05),
    dangerFg: Color(0xFFF87171), dangerBg: Color(0xFF2A1212),
    infoFg: Color(0xFF38BDF8), infoBg: Color(0xFF082530),
    accent: NubiaColors.sand500,
  );

  @override
  NubiaTokens copyWith({Color? textTertiary}) => this; // simplifié : compléter au besoin

  @override
  NubiaTokens lerp(ThemeExtension<NubiaTokens>? other, double t) => this;
}
```

## 3. Constantes layout
```dart
// lib/theme/nubia_metrics.dart
class NubiaSpace { static const x1=4.0,x2=8.0,x3=12.0,x4=16.0,x5=20.0,x6=24.0,x8=32.0,x10=40.0,x12=48.0,x16=64.0; }
class NubiaRadius { static const xs=4.0,sm=6.0,md=8.0,lg=12.0,xl=16.0,full=999.0; }
class NubiaDur { static const fast=Duration(milliseconds:120), base=Duration(milliseconds:200), slow=Duration(milliseconds:320); }
```

## 4. ThemeData (clair + sombre)
```dart
// lib/theme/nubia_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'nubia_colors.dart';
import 'nubia_tokens.dart';
import 'nubia_metrics.dart';

ThemeData _base(ColorScheme scheme, NubiaTokens tokens) {
  final text = GoogleFonts.interTextTheme().apply(
    bodyColor: scheme.onSurface, displayColor: scheme.onSurface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text.copyWith(
      // titres premium en Fraunces
      displayLarge: GoogleFonts.fraunces(fontSize: 32, height: 40/32, fontWeight: FontWeight.w600, color: scheme.onSurface),
      headlineMedium: GoogleFonts.inter(fontSize: 24, height: 32/24, fontWeight: FontWeight.w600, color: scheme.onSurface),
    ),
    extensions: [tokens],
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary, foregroundColor: scheme.onPrimary,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NubiaRadius.md)),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: scheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NubiaRadius.sm),
        borderSide: BorderSide(color: tokens.borderDefault),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NubiaRadius.sm),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface, elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NubiaRadius.lg),
        side: BorderSide(color: tokens.borderSubtle),
      ),
    ),
  );
}

final nubiaLight = _base(
  const ColorScheme.light(
    primary: NubiaColors.brand700, onPrimary: NubiaColors.n0,
    primaryContainer: NubiaColors.brand50, onPrimaryContainer: NubiaColors.brand800,
    secondary: NubiaColors.brand600, onSecondary: NubiaColors.n0,
    surface: NubiaColors.n0, onSurface: NubiaColors.n900,
    error: NubiaColors.dangerFg, onError: NubiaColors.n0,
    outline: NubiaColors.n300,
  ).copyWith(onSurfaceVariant: NubiaColors.n600),
  NubiaTokens.light,
);

final nubiaDark = _base(
  const ColorScheme.dark(
    primary: NubiaColors.brand400, onPrimary: Color(0xFF052E22),
    primaryContainer: Color(0xFF0B3D2E), onPrimaryContainer: NubiaColors.brand200,
    secondary: NubiaColors.brand400, onSecondary: Color(0xFF052E22),
    surface: NubiaColors.n800, onSurface: NubiaColors.n50,
    error: Color(0xFFF87171), onError: Color(0xFF2A1212),
    outline: NubiaColors.n600,
  ).copyWith(onSurfaceVariant: NubiaColors.n300),
  NubiaTokens.dark,
);
```

## 5. Usage
```dart
MaterialApp(
  theme: nubiaLight,
  darkTheme: nubiaDark,
  themeMode: ThemeMode.system, // respecte le réglage OS
);

// lire un token custom dans un widget :
final t = Theme.of(context).extension<NubiaTokens>()!;
Container(color: t.successBg, child: Text('Confirmé', style: TextStyle(color: t.successFg)));
```

## 6. Dépendances
```yaml
# pubspec.yaml
dependencies:
  google_fonts: ^6.2.1
```

> Notes : `copyWith`/`lerp` de `NubiaTokens` sont simplifiés ici — les compléter pour des transitions de thème animées. Respecter `MediaQuery.disableAnimations` / `prefers-reduced-motion`. Composants détaillés : `02-composants.md`.
