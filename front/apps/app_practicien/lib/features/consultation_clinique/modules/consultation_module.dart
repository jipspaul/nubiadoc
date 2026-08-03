import 'package:flutter/material.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../consultation_clinique_state.dart';

/// Points d'extension « spécialité » de la vue consultation au fauteuil.
///
/// Le dentaire est le premier (et seul) module ; l'instance est résolue via
/// GetIt (`pro_di.dart`). Le jour où une deuxième spécialité arrive, le
/// registre devient une `Map<String, ConsultationSpecialtyModule>` résolue
/// par la spécialité du cabinet — une registration à changer, rien d'autre.
///
/// Garde-fou : un module PROPOSE (pré-remplit, affiche), il n'écrit jamais
/// de donnée clinique sans validation explicite du praticien (périmètre
/// non-dispositif-médical, docs/06 §E4.8).
abstract class ConsultationSpecialtyModule {
  const ConsultationSpecialtyModule();

  /// Enveloppe la vue « séance ouverte » des providers du module
  /// (ex. `DentalChartCubit` keyé sur le patient). Appelé uniquement quand
  /// le patient de la séance est connu.
  Widget wrapSession({required String patientId, required Widget child});

  /// Panneau de spécialité en tête de colonne centrale (ex. odontogramme).
  Widget? buildCentralPanel(BuildContext context);

  /// Tuile de spécialité en tête du panneau « Contexte clinique »
  /// (ex. « Dent traitée » avec libellé anatomique).
  Widget? buildContextTile(BuildContext context, String? highlightedTooth);

  /// État des dents pour colorer le sélecteur mobile ; `null` si
  /// indisponible. Doit être appelé sous [wrapSession].
  Map<String, ToothState>? teethStatus(BuildContext context);

  /// Réagit à l'ajout d'un acte portant une dent : peut PROPOSER une mise à
  /// jour (dialogue explicite) — jamais d'écriture automatique.
  Future<void> onToothActRecorded(BuildContext context, AddedToothAct act);
}
