// Quoi : colonne « Contexte » gauche de l'écran consultation au fauteuil
// (encarts « Alertes du dossier », « Dernières séances », « Plan en cours »
// + squelette « à venir » affiché uniquement en l'absence des trois, #6396).
// Quand : rendue par `_LoadedView` (`consultation_clinique_page.dart`)
// uniquement en layout 3 colonnes (largeur disponible ≥ kThreeColumnBreakpoint,
// #4935).
// Pourquoi : extrait de `consultation_clinique_page.dart` (#4954) pour
// redescendre ce fichier sous le plafond de taille CLAUDE.md — même Key
// conditionnelle (`consultation_context_column_layout`). #6386 — l'encart
// « Dernières séances » (`RecentSessionsBox`) a rejoint cette colonne unique :
// il vivait auparavant dans un `LayoutBuilder`/`Row` séparé, propre à
// `_LoadedView`, avec son propre seuil de 1280 px appliqué à la largeur
// *déjà* amputée de cette colonne — deux seuils de 1280 px empilés au lieu
// d'un seul, comme le prescrit la maquette (un unique `.ctx` de 288 px).
// Modes d'échec : aucun — widget purement présentationnel.
import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'active_plan_box.dart';
import 'patient_alerts_box.dart';
import 'recent_sessions_box.dart';

/// Colonne « Contexte » (288 px, ≥ kThreeColumnBreakpoint uniquement) —
/// scaffold #4935. En tête, l'encart « Alertes du dossier » (#4936) quand le
/// dossier porte des alertes médicales passives ([alerts] non vide), puis
/// l'encart « Dernières séances » (#4937, #6386) quand [patientId] est connu,
/// puis l'encart « Plan en cours » (#4938) quand le patient a un plan de
/// traitement actif ([activePlan] non nul et [patientId] connu) ; le
/// squelette « à venir » (#6396) ne s'affiche que si aucun des trois encarts
/// ci-dessus n'est rendu.
class ContextColumn extends StatelessWidget {
  const ContextColumn({
    super.key,
    required this.alerts,
    this.patientId,
    this.sessionId,
    this.activePlan,
  });

  final List<MedicalAlert> alerts;

  /// Id du patient de la séance — requis pour naviguer vers le plan de
  /// traitement depuis l'encart « Plan en cours » (#4938) et pour
  /// l'historique « Dernières séances » (#4937). `null` si absent de la
  /// réponse (route liste) : les deux encarts sont alors masqués.
  final String? patientId;

  /// Séance en cours (#6386) — exclue de l'encart « Dernières séances »,
  /// elle n'est pas "passée". `null` si inconnu (l'historique n'exclut
  /// alors rien).
  final String? sessionId;

  /// Plan de traitement actif du patient (#4938). `null` si le patient n'a
  /// aucun plan `in_progress` : l'encart « Plan en cours » n'est pas rendu.
  final ActivePlanSummary? activePlan;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final showActivePlan = activePlan != null && patientId != null;
    final showRecentSessions = patientId != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 0, 8, 8),
      child: Column(
        // La clé `consultation_context_column_layout` (#4936) n'existe que
        // lorsqu'un encart (alertes, historique ou plan actif) est
        // réellement rendu — sinon la colonne reste le simple squelette
        // « à venir ».
        key: alerts.isEmpty && !showActivePlan && !showRecentSessions
            ? null
            : const Key('consultation_context_column_layout'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (alerts.isNotEmpty) ...[
            PatientAlertsBox(alerts: alerts),
            const SizedBox(height: 12),
          ],
          if (showRecentSessions) ...[
            RecentSessionsBox(
              patientId: patientId!,
              excludeSessionId: sessionId,
            ),
            const SizedBox(height: 12),
          ],
          if (showActivePlan) ...[
            ActivePlanBox(patientId: patientId!, plan: activePlan!),
            const SizedBox(height: 12),
          ],
          if (alerts.isEmpty && !showRecentSessions && !showActivePlan)
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
