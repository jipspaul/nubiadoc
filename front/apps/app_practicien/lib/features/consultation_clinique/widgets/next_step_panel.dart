import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Panneau « Prochaine étape » (maquette) : phase de plan en cours avec
/// décompte de séances (#4120). Les CTA de navigation (programmer le RDV,
/// détail du plan) arrivent au lot 4.
class NextStepPanel extends StatelessWidget {
  const NextStepPanel({super.key, required this.phase});

  final CurrentPhase phase;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final details = <String>[
      'Phase ${phase.position}/${phase.phaseCount} · ${phase.planTitle}',
      if (phase.plannedSessions != null)
        'Séance ${phase.completedSessions}/${phase.plannedSessions}',
    ];

    return NubiaCard(
      child: Column(
        key: const Key('next_step_panel'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Prochaine étape', style: textTheme.titleSmall),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: cs.primaryContainer,
                child: Text(
                  '${phase.position}',
                  style: textTheme.labelMedium?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      phase.phaseTitle,
                      style: textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      details.join(' · '),
                      key: const Key('next_step_details'),
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (phase.nextPhaseTitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Ensuite : ${phase.nextPhaseTitle}',
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
