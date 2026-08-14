import 'package:flutter/material.dart';

/// Formatage monétaire partagé entre toutes les apps (`app_patient`,
/// `app_pharmacie`, …) — un seul helper propriétaire, jamais dupliqué
/// (#4888, extrait de `app_patient/financial_format_utils.dart`, #4061).

const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

/// Formate des centimes en euros avec séparateur de milliers (espace fine
/// insécable) et virgule décimale ; ex. `206000` → « 2 060 € », `8050` →
/// « 80,50 € ». Un montant négatif est préfixé par un « − » typographique.
String formatQuoteCents(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final frac = abs % 100;

  final wholeStr = _groupThousands(whole);
  final body =
      frac == 0 ? wholeStr : '$wholeStr,${frac.toString().padLeft(2, '0')}';
  return '${negative ? '−' : ''}$body €';
}

String _groupThousands(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(' '); // espace fine insécable
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
