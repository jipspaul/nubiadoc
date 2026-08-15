// Quoi : colonne « Contexte » gauche de l'écran consultation au fauteuil
// (encart « Alertes du dossier » + squelette « à venir »).
// Quand : rendue par `_LoadedView` (`consultation_clinique_page.dart`)
// uniquement en layout 3 colonnes (largeur disponible ≥ 1280 px, #4935).
// Pourquoi : extrait de `consultation_clinique_page.dart` (#4954) pour
// redescendre ce fichier sous le plafond de taille CLAUDE.md — aucun
// changement de rendu, même Key conditionnelle
// (`consultation_context_column_layout`).
// Modes d'échec : aucun — widget purement présentationnel.
import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'active_plan_box.dart';
import 'patient_alerts_box.dart';

/// Colonne « Contexte » (288 px, ≥ 1280 px uniquement) — scaffold #4935.
/// En tête, l'encart « Alertes du dossier » (#4936) quand le dossier porte
/// des alertes médicales passives ([alerts] non vide), puis l'encart « Plan
/// en cours » (#4938) quand le patient a un plan de traitement actif
/// ([activePlan] non nul et [patientId] connu) ; le reste (historique) reste
/// un squelette « à venir », ticket dédié.
class ContextColumn extends StatelessWidget {
  const ContextColumn({
    super.key,
    required this.alerts,
    this.patientId,
    this.activePlan,
  });

  final List<MedicalAlert> alerts;

  /// Id du patient de la séance — requis pour naviguer vers le plan de
  /// traitement depuis l'encart « Plan en cours » (#4938). `null` si absent
  /// de la réponse (route liste) : l'encart est alors masqué.
  final String? patientId;

  /// Plan de traitement actif du patient (#4938). `null` si le patient n'a
  /// aucun plan `in_progress` : l'encart « Plan en cours » n'est pas rendu.
  final ActivePlanSummary? activePlan;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final showActivePlan = activePlan != null && patientId != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 0, 8, 8),
      child: Column(
        // La clé `consultation_context_column_layout` (#4936) n'existe que
        // lorsqu'un encart (alertes ou plan actif) est réellement rendu —
        // sinon la colonne reste le simple squelette « à venir ».
        key: alerts.isEmpty && !showActivePlan
            ? null
            : const Key('consultation_context_column_layout'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (alerts.isNotEmpty) ...[
            PatientAlertsBox(alerts: alerts),
            const SizedBox(height: 12),
          ],
          if (showActivePlan) ...[
            ActivePlanBox(patientId: patientId!, plan: activePlan!),
            const SizedBox(height: 12),
          ],
          NubiaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Contexte patient', style: textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(
                  'Historique et plan de traitement arrivent bientôt.',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
