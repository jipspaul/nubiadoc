import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Agrégats du bandeau de compteurs de l'écran Devis (#5092).
///
/// « actifs » = devis ni annulés ni expirés.
class DevisKpis {
  const DevisKpis({
    required this.activeCount,
    required this.pendingSignatureCount,
    required this.expiringSoonCount,
    required this.engagedAmountCents,
  });

  factory DevisKpis.fromQuotes(List<CabinetQuote> quotes, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    var activeCount = 0;
    var pendingSignatureCount = 0;
    var expiringSoonCount = 0;
    var engagedAmountCents = 0;
    for (final quote in quotes) {
      final isActive = quote.status != CabinetQuoteStatus.cancelled &&
          quote.status != CabinetQuoteStatus.expired;
      if (isActive) {
        activeCount++;
        engagedAmountCents += quote.totalCents;
      }
      if (quote.status == CabinetQuoteStatus.sent) {
        pendingSignatureCount++;
        final expiresAt = quote.expiresAt;
        if (expiresAt != null &&
            expiresAt.isAfter(reference) &&
            expiresAt.difference(reference) <= const Duration(days: 7)) {
          expiringSoonCount++;
        }
      }
    }
    return DevisKpis(
      activeCount: activeCount,
      pendingSignatureCount: pendingSignatureCount,
      expiringSoonCount: expiringSoonCount,
      engagedAmountCents: engagedAmountCents,
    );
  }

  final int activeCount;
  final int pendingSignatureCount;
  final int expiringSoonCount;
  final int engagedAmountCents;
}

/// Bandeau de 4 indicateurs dans la barre d'outils de l'écran Devis : devis
/// actifs, en attente de signature (ambre), expirant sous 7 jours (rouge) et
/// montant engagé.
class DevisKpiBar extends StatelessWidget {
  const DevisKpiBar({super.key, required this.quotes});

  final List<CabinetQuote> quotes;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final kpis = DevisKpis.fromQuotes(quotes);

    return Row(
      children: [
        Expanded(
          child: _DevisKpiStat(
            key: const Key('devis_kpi_active'),
            value: '${kpis.activeCount}',
            label: 'devis actifs',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DevisKpiStat(
            key: const Key('devis_kpi_pending_signature'),
            value: '${kpis.pendingSignatureCount}',
            label: 'en attente de signature',
            valueColor: tokens.warningFg,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DevisKpiStat(
            key: const Key('devis_kpi_expiring_soon'),
            value: '${kpis.expiringSoonCount}',
            label: 'expirent sous 7 jours',
            valueColor: tokens.dangerFg,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DevisKpiStat(
            key: const Key('devis_kpi_engaged_amount'),
            value: NubiaMoney.formatCents(kpis.engagedAmountCents),
            label: 'montant engagé',
          ),
        ),
      ],
    );
  }
}

/// Une valeur (chiffres tabulaires) et son libellé, empilés — un indicateur
/// du [DevisKpiBar].
class _DevisKpiStat extends StatelessWidget {
  const _DevisKpiStat({
    super.key,
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
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: valueColor ?? theme.colorScheme.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: tokens.textTertiary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
