import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'treatment_plan_format_utils.dart';

/// Bloc financier honnête du détail d'un plan de soins (#5301) : remplace
/// l'ancien `AmountHeader` (total + reste à charge) par une décomposition en
/// « déjà réglé » / « engagé (devis signé) » / « en attente de votre
/// accord ». Maquette : `design/v2-screens/patient-mon-plan-de-soins.png`.
class PlanCostBlock extends StatelessWidget {
  const PlanCostBlock({super.key, required this.plan});

  final PatientTreatmentPlan plan;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final totalCents = plan.totalCostCents ?? 0;
    final paidCents = plan.paidCents;
    final committedCents = plan.committedCents;
    final pendingCents = plan.pendingApprovalCents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text(
            'CE QUE CELA REPRÉSENTE',
            style: textTheme.labelSmall?.copyWith(
              color: tokens.textTertiary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ),
        Container(
          key: const Key('plan_cost_block'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NubiaColors.n0,
            border: Border.all(color: NubiaColors.n200),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.account_balance_wallet,
                    size: 20,
                    color: NubiaColors.n600,
                  ),
                  const SizedBox(width: 8),
                  Text('Coût de votre plan', style: textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 16),
              _PlanCostTrack(
                paidCents: paidCents,
                committedCents: committedCents,
                pendingCents: pendingCents,
              ),
              const SizedBox(height: 16),
              _PlanCostRow(
                label: 'Total du plan de soins',
                amount: formatTreatmentPlanCents(totalCents),
              ),
              const SizedBox(height: 8),
              _PlanCostRow(
                label: 'Déjà réglé',
                amount: formatTreatmentPlanCents(paidCents),
                amountColor: NubiaColors.brand700,
              ),
              const SizedBox(height: 8),
              _PlanCostRow(
                label: 'Engagé (devis signé)',
                amount: formatTreatmentPlanCents(committedCents),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.only(top: 12),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: NubiaColors.n300)),
                ),
                child: _PlanCostRow(
                  label: 'En attente de votre accord',
                  amount: formatTreatmentPlanCents(pendingCents),
                  amountColor: tokens.warningFg,
                  amountFontSize: 19,
                  amountFontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Barre à segments proportionnels (réglé / engagé / en attente).
class _PlanCostTrack extends StatelessWidget {
  const _PlanCostTrack({
    required this.paidCents,
    required this.committedCents,
    required this.pendingCents,
  });

  final int paidCents;
  final int committedCents;
  final int pendingCents;

  @override
  Widget build(BuildContext context) {
    final segments = <Widget>[
      if (paidCents > 0)
        Expanded(
          flex: paidCents,
          child: Container(color: NubiaColors.brand600),
        ),
      if (committedCents > 0)
        Expanded(
          flex: committedCents,
          child: Container(color: NubiaColors.brand200),
        ),
      if (pendingCents > 0)
        Expanded(
          flex: pendingCents,
          child: Container(color: NubiaColors.n200),
        ),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 12,
        child: segments.isEmpty
            ? Container(color: NubiaColors.n200)
            : Row(children: segments),
      ),
    );
  }
}

class _PlanCostRow extends StatelessWidget {
  const _PlanCostRow({
    required this.label,
    required this.amount,
    this.amountColor,
    this.amountFontSize,
    this.amountFontWeight,
  });

  final String label;
  final String amount;
  final Color? amountColor;
  final double? amountFontSize;
  final FontWeight? amountFontWeight;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, style: textTheme.bodyMedium)),
        const SizedBox(width: 12),
        Text(
          amount,
          style: textTheme.bodyMedium?.copyWith(
            color: amountColor,
            fontSize: amountFontSize,
            fontWeight: amountFontWeight ?? FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
