import 'package:nubia_design_system/nubia_design_system.dart';

/// Unique source du mapping statut brut API → (libellé FR, [StatusPillVariant])
/// pour l'écran praticien « Plan de traitement » (#5004) — évite que
/// `plan.status`/`phase.status` (ex. `in_progress`, `draft`) soit affiché tel
/// quel. Statut inconnu → libellé = la chaîne brute (toujours dans un
/// [StatusPill], jamais du texte nu) et variant [StatusPillVariant.info].

/// Style du pill pour un statut de PLAN, réutilise le vocabulaire partagé
/// avec `app_patient` ([treatmentPlanStatusLabels]/[treatmentPlanStatusVariants]).
(String label, StatusPillVariant variant) treatmentPlanStatusStyle(
  String status,
) {
  return (
    treatmentPlanStatusLabels[status] ?? status,
    treatmentPlanStatusVariants[status] ?? StatusPillVariant.info,
  );
}

/// Libellés/couleurs du statut de phase (#5006, maquette design-v2 point 1)
/// — vocabulaire `PHASE_STATUS_ORDER` côté API (`requested`/`confirmed`/
/// `in_progress`/`done`), formulé côté praticien (distinct du libellé
/// patient de `treatment_plan_detail_page.dart`).
const _phaseStatusLabels = {
  'requested': 'Planifiée',
  'confirmed': 'Confirmée',
  'in_progress': 'En cours',
  'done': 'Terminée',
};

const _phaseStatusVariants = {
  'requested': StatusPillVariant.neutral,
  'confirmed': StatusPillVariant.info,
  'in_progress': StatusPillVariant.warning,
  'done': StatusPillVariant.success,
};

/// Style du pill pour un statut de PHASE — voir [treatmentPlanStatusStyle].
(String label, StatusPillVariant variant) treatmentPhaseStatusStyle(
  String status,
) {
  return (
    _phaseStatusLabels[status] ?? status,
    _phaseStatusVariants[status] ?? StatusPillVariant.info,
  );
}
