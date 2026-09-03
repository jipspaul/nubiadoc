import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Agrégats du bandeau de compteurs de l'écran Stock (#4900).
class StockKpis {
  const StockKpis({
    required this.toRespondCount,
    required this.toDeliverCount,
    required this.fulfilledCount,
    required this.partnerCabinetsCount,
  });

  factory StockKpis.fromRequests(List<StockRequest> requests, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    var toRespondCount = 0;
    var toDeliverCount = 0;
    var fulfilledCount = 0;
    final cabinetNames = <String>{};
    for (final request in requests) {
      switch (request.status) {
        case StockRequestStatus.sent:
          toRespondCount++;
        case StockRequestStatus.accepted:
          toDeliverCount++;
        case StockRequestStatus.fulfilled:
          final fulfilledAt = request.fulfilledAt;
          if (fulfilledAt != null && _isSameMonth(fulfilledAt, reference)) {
            fulfilledCount++;
          }
        case StockRequestStatus.rejected:
        case StockRequestStatus.cancelled:
          break;
      }
      final cabinetName = request.cabinetName;
      if (cabinetName != null) {
        cabinetNames.add(cabinetName);
      }
    }
    return StockKpis(
      toRespondCount: toRespondCount,
      toDeliverCount: toDeliverCount,
      fulfilledCount: fulfilledCount,
      partnerCabinetsCount: cabinetNames.length,
    );
  }

  final int toRespondCount;
  final int toDeliverCount;
  final int fulfilledCount;
  final int partnerCabinetsCount;

  String get partnerCabinetsLabel =>
      partnerCabinetsCount == 1 ? 'cabinet partenaire' : 'cabinets partenaires';
}

bool _isSameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

/// Bandeau de compteurs en tête de l'écran Stock : demandes à répondre
/// (rouge), acceptées à livrer (ambre), honorées ce mois et cabinets
/// partenaires.
class StockKpiBanner extends StatelessWidget {
  const StockKpiBanner({super.key, required this.requests});

  final List<StockRequest> requests;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final kpis = StockKpis.fromRequests(requests);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _StockKpiStat(
              value: '${kpis.toRespondCount}',
              label: 'à répondre',
              valueColor: tokens.dangerFg,
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: _StockKpiStat(
              value: '${kpis.toDeliverCount}',
              label: 'acceptées, à livrer',
              valueColor: tokens.warningFg,
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: _StockKpiStat(
              value: '${kpis.fulfilledCount}',
              label: 'honorées ce mois',
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: _StockKpiStat(
              value: '${kpis.partnerCabinetsCount}',
              label: kpis.partnerCabinetsLabel,
            ),
          ),
        ],
      ),
    );
  }
}

/// Une valeur (chiffres tabulaires) et son libellé, empilés — un compteur du
/// [StockKpiBanner].
class _StockKpiStat extends StatelessWidget {
  const _StockKpiStat({
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
