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

import 'patient_alerts_box.dart';

/// Colonne « Contexte » (288 px, ≥ 1280 px uniquement) — scaffold #4935.
/// En tête, l'encart « Alertes du dossier » (#4936) quand le dossier porte
/// des alertes médicales passives ([alerts] non vide) ; le reste (historique,
/// plan de traitement) reste un squelette « à venir », tickets dédiés.
class ContextColumn extends StatelessWidget {
  const ContextColumn({super.key, required this.alerts});

  final List<MedicalAlert> alerts;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 0, 8, 8),
      child: Column(
        // La clé `consultation_context_column_layout` (#4936) n'existe que
        // lorsqu'un encart d'alertes est réellement rendu — sinon la colonne
        // reste le simple squelette « à venir ».
        key: alerts.isEmpty
            ? null
            : const Key('consultation_context_column_layout'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (alerts.isNotEmpty) ...[
            PatientAlertsBox(alerts: alerts),
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
