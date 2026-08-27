import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

/// Pied de panneau détail d'un plan de traitement (#5020, maquette
/// design-v2 point 3) : montant réalisé et montant engagé (devis signé) à
/// gauche, avertissement ambre à droite sur la part du plan non couverte par
/// un devis — masqué quand tout le plan est couvert (`remainingToQuoteCents`
/// à 0).
///
/// [realizedCents]/[engagedCents]/[remainingToQuoteCents] proviennent des
/// agrégats de montants du plan (`TreatmentPlan.realizedCents`/
/// `engagedCents`/`remainingToQuoteCents`, ticket domaine « agrégats de
/// montants », #5013).
class PlanFooter extends StatelessWidget {
  const PlanFooter({
    super.key,
    required this.realizedCents,
    required this.engagedCents,
    required this.remainingToQuoteCents,
    this.warningKey,
  });

  final int realizedCents;
  final int engagedCents;
  final int remainingToQuoteCents;
  final Key? warningKey;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final amountStyle = textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: tabularFigures,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AmountLine(
                label: 'Réalisé : ',
                amount: NubiaMoney.formatCents(realizedCents),
                amountStyle: amountStyle,
              ),
              const SizedBox(height: 4),
              _AmountLine(
                label: 'Engagé (devis signé) : ',
                amount: NubiaMoney.formatCents(engagedCents),
                amountStyle: amountStyle,
              ),
            ],
          ),
        ),
        if (remainingToQuoteCents > 0) ...[
          const SizedBox(width: 12),
          Expanded(
            child: _UncoveredWarning(
              key: warningKey,
              amount: NubiaMoney.formatCents(remainingToQuoteCents),
            ),
          ),
        ],
      ],
    );
  }
}

class _AmountLine extends StatelessWidget {
  const _AmountLine({
    required this.label,
    required this.amount,
    required this.amountStyle,
  });

  final String label;
  final String amount;
  final TextStyle? amountStyle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Text.rich(
      TextSpan(
        style: textTheme.bodySmall,
        children: [
          TextSpan(text: label),
          TextSpan(text: amount, style: amountStyle),
        ],
      ),
    );
  }
}

/// Encadré `.warn` de la maquette : fond `warnBg`, bordure ambre, icône
/// `info` — le montant du plan qu'aucun devis ne couvre encore.
class _UncoveredWarning extends StatelessWidget {
  const _UncoveredWarning({super.key, required this.amount});

  final String amount;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NubiaColors.warningBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: tokens.warningFg),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: textTheme.bodySmall?.copyWith(color: tokens.warningFg),
                children: [
                  TextSpan(
                    text: amount,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(
                    text: ' du plan ne sont couverts par aucun devis',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
