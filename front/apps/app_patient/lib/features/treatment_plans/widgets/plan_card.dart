import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../../router/app_router.dart';
import 'treatment_plan_format_utils.dart';

/// Carte riche d'un plan de la liste (#5288) : titre + pastille de statut,
/// sous-titre praticien + date, barre de progression segmentée, étape
/// courante et montant, et — quand programmée — la rangée « Prochaine
/// séance » (#5289). Remplace l'ancienne `ListRow` (titre + pastille
/// seulement). Maquette : `design/v2-screens/patient-mon-plan-de-soins.png`.
class PlanCard extends StatelessWidget {
  const PlanCard({super.key, required this.plan});

  final PatientTreatmentPlan plan;

  @override
  Widget build(BuildContext context) {
    final nextAppointmentAt = plan.nextAppointmentAt;
    final stepCount = plan.stepCount;

    final subtitleParts = <String>[
      if (plan.practitionerName != null) 'Dr ${plan.practitionerName}',
      if (plan.proposedAt != null)
        'proposé le ${formatTreatmentPlanDayMonth(plan.proposedAt!.toLocal())}',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: NubiaCard(
        key: Key('treatment_plan_${plan.id}'),
        state: NubiaCardState.interactive,
        onTap: () => context.push('/treatment-plans/${plan.id}'),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 12),
                StatusPill(
                  label: treatmentPlanStatusLabels[plan.status] ?? plan.status,
                  variant: treatmentPlanStatusVariants[plan.status] ??
                      StatusPillVariant.info,
                ),
              ],
            ),
            if (subtitleParts.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitleParts.join(' · '),
                style: const TextStyle(fontSize: 12.5, color: NubiaColors.n500),
              ),
            ],
            if (stepCount != null && stepCount > 0) ...[
              const SizedBox(height: 10),
              _PlanProgressBar(
                key: Key('treatment_plan_${plan.id}_progress'),
                stepCount: stepCount,
                currentStep: plan.currentStep,
                done: plan.status == 'done',
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      [
                        'Étape ${plan.currentStep ?? stepCount} sur $stepCount',
                        if (plan.currentPhaseTitle != null)
                          plan.currentPhaseTitle!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 12.5, color: NubiaColors.n600),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    formatTreatmentPlanCents(plan.totalCostCents ?? 0),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ],
              ),
            ],
            if (nextAppointmentAt != null)
              _NextAppointmentRow(plan: plan, appointmentAt: nextAppointmentAt),
          ],
        ),
      ),
    );
  }
}

/// Barre `.pg` de progression segmentée — un segment par étape, plein
/// `--brand600` pour les étapes faites, `--brand200` pour l'étape courante,
/// `--n200` pour les étapes à venir (#5288). Un plan `done` n'a pas d'étape
/// courante : toutes ses étapes s'affichent pleines.
class _PlanProgressBar extends StatelessWidget {
  const _PlanProgressBar({
    super.key,
    required this.stepCount,
    required this.currentStep,
    required this.done,
  });

  final int stepCount;
  final int? currentStep;
  final bool done;

  Color _colorFor(int segmentIndex) {
    if (done) return NubiaColors.brand600;
    if (currentStep != null) {
      if (segmentIndex < currentStep! - 1) return NubiaColors.brand600;
      if (segmentIndex == currentStep! - 1) return NubiaColors.brand200;
    }
    return NubiaColors.n200;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 6,
      child: Row(
        children: [
          for (var i = 0; i < stepCount; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: _colorFor(i),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Rangée `.nx` en pied de carte — icône + « Prochaine séance » (jour/heure
/// en gras) + lien « Voir » qui ouvre le rendez-vous, indépendamment du tap
/// global de la carte vers le détail du plan (#5289).
class _NextAppointmentRow extends StatelessWidget {
  const _NextAppointmentRow({required this.plan, required this.appointmentAt});

  final PatientTreatmentPlan plan;
  final DateTime appointmentAt;

  @override
  Widget build(BuildContext context) {
    final local = appointmentAt.toLocal();
    final label = '${formatTreatmentPlanWeekdayDayMonth(local)}, '
        '${formatTreatmentPlanTime(local)}';

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(top: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: NubiaColors.n100)),
      ),
      child: Row(
        children: [
          const Icon(Icons.event, size: 16, color: NubiaColors.brand700),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              key: Key('treatment_plan_${plan.id}_next_appointment_label'),
              TextSpan(
                style: const TextStyle(fontSize: 12.5, color: NubiaColors.n600),
                children: [
                  const TextSpan(text: 'Prochaine séance '),
                  TextSpan(
                    text: label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            key: Key('treatment_plan_${plan.id}_next_appointment_cta'),
            onTap: () =>
                context.push('${AppRouter.mesRdv}?id=${plan.nextAppointmentId}'),
            child: const Text(
              'Voir',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: NubiaColors.brand700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
