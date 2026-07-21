import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Formatage partagé de l'écran financier (montants, dates, statut) —
/// extrait de `financial_page.dart` (#4061, CLAUDE.md plafond 700 lignes).

const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

/// Mapping statut domaine ([QuoteStatus]) → libellé FR + variant [StatusPill].
class QuoteStatusStyle {
  const QuoteStatusStyle(this.label, this.variant);

  final String label;
  final StatusPillVariant variant;

  static QuoteStatusStyle of(QuoteStatus status) => switch (status) {
        QuoteStatus.draft =>
          const QuoteStatusStyle('Brouillon', StatusPillVariant.info),
        QuoteStatus.sent =>
          const QuoteStatusStyle('À signer', StatusPillVariant.warning),
        QuoteStatus.signed =>
          const QuoteStatusStyle('Signé', StatusPillVariant.success),
        QuoteStatus.expired =>
          const QuoteStatusStyle('Expiré', StatusPillVariant.error),
        QuoteStatus.cancelled =>
          const QuoteStatusStyle('Annulé', StatusPillVariant.error),
      };
}

String formatQuoteDate(DateTime dt) =>
    '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

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
