import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Agrégats du bandeau de compteurs de l'écran Devis (#4897).
///
/// « actifs » = tous les devis suivis à l'écran (`quotes.length`) ; le
/// compteur « brouillons non envoyés » fait l'objet d'un autre ticket
/// (voir point 8 des notes design) et n'est pas calculé ici.
class DevisKpis {
  const DevisKpis({
    required this.activeCount,
    required this.pendingCount,
    required this.acceptedAmountCents,
  });

  factory DevisKpis.fromQuotes(List<PharmacyQuote> quotes) {
    var pendingCount = 0;
    var acceptedAmountCents = 0;
    for (final quote in quotes) {
      if (quote.status == PharmacyQuoteStatus.sent) {
        pendingCount++;
      } else if (quote.status == PharmacyQuoteStatus.accepted) {
        acceptedAmountCents += quote.totalCents;
      }
    }
    return DevisKpis(
      activeCount: quotes.length,
      pendingCount: pendingCount,
      acceptedAmountCents: acceptedAmountCents,
    );
  }

  final int activeCount;
  final int pendingCount;
  final int acceptedAmountCents;
}

/// Bandeau de compteurs en tête de l'écran Devis : devis actifs, en attente
/// de réponse (ambre) et montant accepté.
class DevisKpiBanner extends StatelessWidget {
  const DevisKpiBanner({super.key, required this.quotes});

  final List<PharmacyQuote> quotes;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final kpis = DevisKpis.fromQuotes(quotes);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DevisKpiStat(
            value: '${kpis.activeCount}',
            label: 'devis actifs',
          ),
          const SizedBox(width: 24),
          _DevisKpiStat(
            value: '${kpis.pendingCount}',
            label: 'en attente de réponse',
            valueColor: tokens.warningFg,
          ),
          const SizedBox(width: 24),
          _DevisKpiStat(
            value: CurrencyUtils.format(kpis.acceptedAmountCents),
            label: 'montant accepté',
          ),
        ],
      ),
    );
  }
}

/// Une valeur (chiffres tabulaires) et son libellé, empilés — un compteur du
/// [DevisKpiBanner].
class _DevisKpiStat extends StatelessWidget {
  const _DevisKpiStat({
    required this.value,
    required this.label,
    this.valueColor,
  });

  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            color: valueColor ?? theme.colorScheme.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.textTertiary,
          ),
        ),
      ],
    );
  }
}
