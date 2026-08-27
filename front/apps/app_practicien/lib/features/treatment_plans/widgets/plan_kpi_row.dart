import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

/// Trois KPIs `.kpi` de l'en-tête de panneau détail d'un plan de traitement
/// (#5017, maquette design-v2 point `.dth`) : « Total du plan » (mis en
/// avant), « Devis signé » et « Reste à deviser ».
///
/// [totalCents]/[signedCents]/[remainingToQuoteCents] proviennent des
/// agrégats de montants du plan (`TreatmentPlan.totalCents`/`engagedCents`/
/// `remainingToQuoteCents`, ticket domaine « agrégats de montants », #5013).
class PlanKpiRow extends StatelessWidget {
  const PlanKpiRow({
    super.key,
    required this.totalCents,
    required this.signedCents,
    required this.remainingToQuoteCents,
  });

  final int totalCents;
  final int signedCents;
  final int remainingToQuoteCents;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _Kpi(
            key: const Key('plan_kpi_total'),
            label: 'TOTAL DU PLAN',
            amount: NubiaMoney.formatCents(totalCents),
            large: true,
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: _Kpi(
            key: const Key('plan_kpi_signed'),
            label: 'DEVIS SIGNÉ',
            amount: NubiaMoney.formatCents(signedCents),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: _Kpi(
            key: const Key('plan_kpi_remaining'),
            label: 'RESTE À DEVISER',
            amount: NubiaMoney.formatCents(remainingToQuoteCents),
          ),
        ),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    super.key,
    required this.label,
    required this.amount,
    this.large = false,
  });

  final String label;
  final String amount;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          amount,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (large ? textTheme.headlineSmall : textTheme.titleMedium)
              ?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w700,
            fontFeatures: tabularFigures,
          ),
        ),
      ],
    );
  }
}
