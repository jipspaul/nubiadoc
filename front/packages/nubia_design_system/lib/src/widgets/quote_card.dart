// lib/presentation/widgets/quote_card.dart
import 'package:flutter/material.dart';
import 'package:nubia_design_system/src/theme/nubia_tokens.dart';
import 'package:nubia_design_system/src/widgets/nubia_button.dart';
import 'package:nubia_design_system/src/widgets/nubia_card.dart';
import 'package:nubia_design_system/src/widgets/status_pill.dart';

/// Statut d'un devis dans le WEDGE (devis → signature → paiement).
enum QuoteCardStatus {
  /// Brouillon (non encore envoyé).
  draft,

  /// Envoyé au patient, à signer.
  sent,

  /// Signé électroniquement.
  signed,

  /// Payé (acompte ou solde).
  paid,

  /// Expiré (délai de validité dépassé).
  expired,

  /// Refusé par le patient.
  refused,
}

/// Une ligne d'acte d'un devis : libellé + montant formaté.
@immutable
class QuoteLine {
  const QuoteLine({required this.label, required this.amount, this.detail});

  /// Libellé de l'acte (aligné à gauche).
  final String label;

  /// Montant formaté (ex. « 1 200 € »), aligné à droite en tabulaire.
  final String amount;

  /// Sous-ligne optionnelle sous le libellé (ex. « Part AMO : 70,00 € »,
  /// #4063 : ventilation AMO/AMC par acte). `null` = pas de sous-ligne.
  final String? detail;
}

/// Carte devis du WEDGE financier.
///
/// Compose un [NubiaCard] : en-tête (titre + badge statut via [StatusPill]),
/// lignes d'actes alignées (libellé gauche / montant droite en chiffres
/// tabulaires), ligne total optionnelle et CTA principal ([NubiaButton]).
///
/// - [title] : titre du plan de soins.
/// - [status] : statut du devis (badge via [StatusPill]).
/// - [lines] : lignes d'actes.
/// - [subtitle] : sous-titre optionnel (ex. praticien).
/// - [totalLabel] / [total] : ligne total optionnelle (montant tabulaire, gras).
/// - [ctaLabel] / [onCtaPressed] : CTA principal optionnel.
///
/// Réfs mockup : `design/mockups/lib/screens-wedge.jsx` (WedgeLines + Card).
class QuoteCard extends StatelessWidget {
  const QuoteCard({
    super.key,
    required this.title,
    required this.status,
    required this.lines,
    this.subtitle,
    this.totalLabel = 'Total',
    this.total,
    this.ctaLabel,
    this.onCtaPressed,
  });

  final String title;
  final QuoteCardStatus status;
  final List<QuoteLine> lines;
  final String? subtitle;
  final String totalLabel;
  final String? total;
  final String? ctaLabel;
  final VoidCallback? onCtaPressed;

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = theme.extension<NubiaTokens>()!;
    final _StatusStyle statusStyle = _StatusStyle.of(status);
    final bool hasCta = ctaLabel != null && onCtaPressed != null;

    return NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // En-tête : titre + badge statut.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              StatusPill(
                label: statusStyle.label,
                variant: statusStyle.variant,
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Lignes d'actes alignées.
          for (int i = 0; i < lines.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          lines[i].label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        lines[i].amount,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w500,
                          fontFeatures: _tabular,
                        ),
                      ),
                    ],
                  ),
                  if (lines[i].detail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      lines[i].detail!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          // Ligne total optionnelle.
          if (total != null) ...[
            Divider(height: 1, thickness: 1, color: tokens.borderDefault),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      totalLabel,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    total!,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                      fontFeatures: _tabular,
                    ),
                  ),
                ],
              ),
            ),
          ],
          // CTA principal.
          if (hasCta) ...[
            const SizedBox(height: 16),
            NubiaButton(
              label: ctaLabel!,
              onPressed: onCtaPressed,
              size: NubiaButtonSize.lg,
            ),
          ],
        ],
      ),
    );
  }
}

/// Mapping statut → libellé FR + variant [StatusPill].
@immutable
class _StatusStyle {
  const _StatusStyle(this.label, this.variant);

  final String label;
  final StatusPillVariant variant;

  static _StatusStyle of(QuoteCardStatus status) {
    switch (status) {
      case QuoteCardStatus.draft:
        return const _StatusStyle('Brouillon', StatusPillVariant.info);
      case QuoteCardStatus.sent:
        return const _StatusStyle('À signer', StatusPillVariant.warning);
      case QuoteCardStatus.signed:
        return const _StatusStyle('Signé', StatusPillVariant.success);
      case QuoteCardStatus.paid:
        return const _StatusStyle('Payé', StatusPillVariant.success);
      case QuoteCardStatus.expired:
        return const _StatusStyle('Expiré', StatusPillVariant.error);
      case QuoteCardStatus.refused:
        return const _StatusStyle('Refusé', StatusPillVariant.error);
    }
  }
}
