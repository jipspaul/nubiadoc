import 'package:flutter/material.dart';

/// Formatage monétaire partagé entre toutes les apps (`app_patient`,
/// `app_pharmacie`, …) — un seul helper propriétaire, jamais dupliqué
/// (#4888, extrait de `app_patient/financial_format_utils.dart`, #4061).

const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

/// Formate des centimes en euros avec séparateur de milliers (espace fine
/// insécable) et virgule décimale ; ex. `206000` → « 2 060 € », `8050` →
/// « 80,50 € ». Un montant négatif est préfixé par un « − » typographique.
///
/// [alwaysShowDecimals] force l'affichage des deux décimales même quand elles
/// sont nulles (ex. `146000` → « 1 460,00 € » plutôt que « 1 460 € ») — requis
/// par certaines maquettes (#4953).
String formatQuoteCents(int cents, {bool alwaysShowDecimals = false}) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final frac = abs % 100;

  final wholeStr = _groupThousands(whole);
  final showDecimals = alwaysShowDecimals || frac != 0;
  final body = showDecimals
      ? '$wholeStr,${frac.toString().padLeft(2, '0')}'
      : wholeStr;
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

/// Fondation 1 du backlog monétaire (#5123) : point d'entrée `NubiaMoney.*`
/// destiné à remplacer à terme `formatQuoteCents` et les formateurs locaux
/// dupliqués (ex. `_formatBalance`) — enrobe [formatQuoteCents] pour ne pas
/// re-diverger sur l'algorithme de regroupement des milliers.
class NubiaMoney {
  const NubiaMoney._();

  /// Centimes → euros toujours avec deux décimales et séparateur de
  /// milliers ; ex. `124567` → « 1 245,67 € », `0` → « 0,00 € ».
  static String formatCents(int cents) =>
      formatQuoteCents(cents, alwaysShowDecimals: true);
}
