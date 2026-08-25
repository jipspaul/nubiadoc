import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../../router/app_router.dart';
import 'treatment_plan_format_utils.dart';

const _subtitleColor = Color(0xFF92400E);
const _amountLineColor = Color(0xFF78350F);
const _footerRuleColor = Color(0xFFFCD34D);

/// Carte `.pc` teintée warning pour un devis reçu et non signé qui porte sur
/// un plan entier — sortie du flux normal, sa propre carte dans la section
/// « À votre décision » de la liste des plans (#5291). Maquette :
/// `design/v2-screens/patient-mon-plan-de-soins.png`.
class PendingQuoteCard extends StatelessWidget {
  const PendingQuoteCard({super.key, required this.plan});

  final PatientTreatmentPlan plan;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final receivedAt = plan.pendingQuoteReceivedAt;
    final receivedAtLabel = receivedAt != null
        ? formatTreatmentPlanDayMonth(receivedAt.toLocal())
        : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.warningBg,
        border: Border.all(color: NubiaColors.warningBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(plan.title, style: textTheme.titleSmall)),
              const SizedBox(width: 8),
              const StatusPill(
                label: 'À accepter',
                variant: StatusPillVariant.warning,
              ),
            ],
          ),
          if (plan.pendingQuoteLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              plan.pendingQuoteLabel!,
              style: const TextStyle(fontSize: 13, color: _subtitleColor),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Reste à votre charge estimé',
                style: TextStyle(fontSize: 13, color: _amountLineColor),
              ),
              Text(
                formatTreatmentPlanCents(
                    plan.pendingQuotePatientShareCents ?? 0),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _amountLineColor,
                  fontFeatures: tabularFigures,
                ),
              ),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _footerRuleColor)),
            ),
            child: Row(
              children: [
                Icon(Icons.description, size: 16, color: tokens.warningFg),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    receivedAtLabel != null
                        ? 'Devis reçu le $receivedAtLabel'
                        : 'Devis reçu',
                    style: const TextStyle(fontSize: 12, color: _amountLineColor),
                  ),
                ),
                GestureDetector(
                  key: Key('pending_quote_${plan.id}_consult_cta'),
                  onTap: () => context
                      .push('${AppRouter.financial}?id=${plan.pendingQuoteId}'),
                  child: const Text(
                    'Consulter',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _amountLineColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
