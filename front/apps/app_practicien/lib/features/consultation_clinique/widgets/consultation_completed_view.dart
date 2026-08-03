import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

/// Écran de clôture de séance. Enrichi au lot 4 (facture générée, prochaine
/// étape du plan, `sessions_remaining`) — extraction telle quelle pour
/// l'instant (règle « 1 widget = 1 fichier »).
class ConsultationCompletedView extends StatelessWidget {
  const ConsultationCompletedView({super.key});

  @override
  Widget build(BuildContext context) {
    return const NubiaEmptyState(
      key: Key('consultation_completed'),
      icon: Icons.check_circle_outline,
      title: 'Consultation terminée',
      subtitle: 'Les actes ont été enregistrés.',
    );
  }
}
