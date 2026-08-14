import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Formatage partagé de l'écran financier (montants, dates, statut) —
/// extrait de `financial_page.dart` (#4061, CLAUDE.md plafond 700 lignes).
///
/// `tabularFigures`/`formatQuoteCents` vivent désormais dans
/// `nubia_design_system` (#4888) — un seul helper propriétaire partagé avec
/// `app_pharmacie`, réexporté ici pour ne pas casser les imports existants.
export 'package:nubia_design_system/nubia_design_system.dart'
    show tabularFigures, formatQuoteCents;

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
