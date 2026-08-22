import 'package:nubia_design_system/src/widgets/status_pill.dart';

/// Vocabulaire de statut des plans de traitement, partagé entre `app_patient`
/// et `app_practicien` (#5304) — un seul statut ⇒ un seul libellé FR, quel
/// que soit qui regarde le plan.

const treatmentPlanStatusLabels = {
  'draft': 'Brouillon',
  'proposed': 'Proposé',
  'accepted': 'Accepté',
  'in_progress': 'En cours',
  'done': 'Terminé',
};

const treatmentPlanStatusVariants = {
  'draft': StatusPillVariant.info,
  'proposed': StatusPillVariant.warning,
  'accepted': StatusPillVariant.success,
  'in_progress': StatusPillVariant.warning,
  'done': StatusPillVariant.success,
};
