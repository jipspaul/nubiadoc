// Quoi : colonne « Arcade + actes » (schéma dentaire, encart « Actes de la
// séance »).
// Quand : rendue par `_LoadedView` (`consultation_clinique_page.dart`) dans
// les trois layouts (1/2/3 colonnes) de l'écran consultation au fauteuil.
// Pourquoi : extrait de `consultation_clinique_page.dart` (#4954) pour
// redescendre ce fichier sous le plafond de taille CLAUDE.md.
// #4968 — le scan de stérilisation est désormais rattaché à chaque ligne
// d'acte (`ActTile`/`_SterilizationStatusBadge`, clé
// `sterilization_scan_act_button_<id>`) : le bouton global qui visait
// `session.acts.last` a été retiré.
// Modes d'échec : aucun — `scrollable` gère son propre défilement en layout
// 2/3 colonnes (hauteur bornée par la Row parente) ; en 1 colonne elle est
// déjà intégrée au `SingleChildScrollView` du parent, donc `scrollable` doit
// rester `false` dans ce cas pour éviter un double scroll imbriqué.
import 'package:flutter/material.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'acts_of_session_card.dart';
import 'dental_status_box.dart';

/// Colonne « Arcade + actes » — sélecteur de dent et liste des actes
/// enregistrés. `scrollable` gère son propre défilement en layout 2/3
/// colonnes (hauteur bornée par la Row) ; en 1 colonne elle est déjà
/// intégrée au `SingleChildScrollView` parent.
class CenterColumn extends StatelessWidget {
  const CenterColumn({
    super.key,
    required this.session,
    required this.selectedTooth,
    required this.onToothTap,
    required this.scrollable,
  });

  final ClinicalSession session;
  final String? selectedTooth;
  final ValueChanged<String> onToothTap;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: DentalStatusBox(
            patientId: session.patientId,
            sessionActs: session.acts,
            selectedTooth: selectedTooth,
            onToothTap: onToothTap,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ActsOfSessionCard(session: session),
        ),
      ],
    );
    return scrollable ? SingleChildScrollView(child: content) : content;
  }
}
