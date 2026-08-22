import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

const _phaseStateLabels = {
  'requested': 'demandée',
  'confirmed': 'confirmée',
  'in_progress': 'en cours',
  'done': 'réalisée',
};

/// Bandeau héros « Où vous en êtes » en tête du détail d'un plan — répond
/// d'abord à « il me reste combien d'étapes ? » plutôt que d'afficher le
/// simple titre du plan, déjà porté par l'AppBar (#5295). Maquette :
/// `design/v2-screens/patient-mon-plan-de-soins.png`.
///
/// [phases] doit déjà être trié par [PatientTreatmentPlanPhase.position].
class PlanHero extends StatelessWidget {
  const PlanHero({super.key, required this.phases});

  final List<PatientTreatmentPlanPhase> phases;

  @override
  Widget build(BuildContext context) {
    if (phases.isEmpty) return const SizedBox.shrink();

    var currentIndex =
        phases.indexWhere((phase) => phase.status == 'in_progress');
    if (currentIndex == -1) {
      currentIndex = phases.indexWhere((phase) => phase.status != 'done');
    }
    if (currentIndex == -1) currentIndex = phases.length - 1;
    final current = phases[currentIndex];
    final stateLabel = _phaseStateLabels[current.status] ?? current.status;

    return Container(
      key: const Key('treatment_plan_hero'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: NubiaColors.brand700,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OÙ VOUS EN ÊTES',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: Colors.white.withValues(alpha: .8),
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Étape ${currentIndex + 1} sur ${phases.length}',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '${current.title} · $stateLabel',
            style: TextStyle(
              fontSize: 13.5,
              color: Colors.white.withValues(alpha: .85),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final (index, phase) in phases.indexed) ...[
                if (index > 0) const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: phase.status == 'done'
                          ? Colors.white
                          : Colors.white.withValues(alpha: .3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
