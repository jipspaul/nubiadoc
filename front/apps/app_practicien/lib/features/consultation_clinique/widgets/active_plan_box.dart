import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Encart « Plan en cours » de la colonne contexte gauche de la vue fauteuil
/// (≥ 1280 px, maquette `praticien-consultation-pc.png`, #4938) : titre du
/// plan de traitement actif, progression segmentée par phase et lien vers
/// l'écran de plan de traitement du patient.
///
/// N'est rendu que si le patient a un plan `in_progress` avec au moins une
/// phase (voir `ClinicalSession.activePlan`) — jamais de plan inventé.
class ActivePlanBox extends StatelessWidget {
  const ActivePlanBox({
    super.key,
    required this.patientId,
    required this.plan,
  });

  final String patientId;
  final ActivePlanSummary plan;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return NubiaCard(
      child: Column(
        key: const Key('active_plan_box'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment, size: 18, color: NubiaColors.brand600),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Plan en cours',
                  style: textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            plan.title,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < plan.totalPhases; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i < plan.currentPhase
                          ? NubiaColors.brand600
                          : NubiaColors.n200,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Phase ${plan.currentPhase} sur ${plan.totalPhases} · '
            '${formatQuoteCents(plan.totalCostCents)}',
            style: textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            key: const Key('active_plan_open_link'),
            onTap: () => context.push('/patients/$patientId/treatment-plans'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ouvrir le plan',
                  style: textTheme.bodySmall?.copyWith(
                    color: NubiaColors.brand700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.arrow_forward,
                  size: 14,
                  color: NubiaColors.brand700,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
