import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

/// Thème de test léger : évite l'appel réseau de `google_fonts` tout en
/// exposant le [ColorScheme] Nubia et l'extension [NubiaTokens] dont dépendent
/// les widgets du design system.
ThemeData _testTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: NubiaColors.brand700,
      onPrimary: NubiaColors.n0,
      surface: NubiaColors.n0,
      onSurface: NubiaColors.n900,
      onSurfaceVariant: NubiaColors.n600,
      error: NubiaColors.dangerFg,
      onError: NubiaColors.n0,
      outline: NubiaColors.n300,
    ),
    extensions: const [NubiaTokens.light],
  );
}

/// Enveloppe [child] dans un [MaterialApp] + [Scaffold] prêts pour les tests.
Widget wrap(Widget child) {
  return MaterialApp(
    theme: _testTheme(),
    home: Scaffold(body: Center(child: child)),
  );
}
