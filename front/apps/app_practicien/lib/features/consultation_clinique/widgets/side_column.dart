// Quoi : colonne « Saisie + note » (recherche/ajout d'acte CCAM et note de
// séance avec auto-save).
// Quand : rendue par `_LoadedView` (`consultation_clinique_page.dart`) dans
// les trois layouts (1/2/3 colonnes) de l'écran consultation au fauteuil.
// Pourquoi : extrait de `consultation_clinique_page.dart` (#4954) pour
// redescendre ce fichier sous le plafond de taille CLAUDE.md — aucun
// changement de rendu, mêmes Keys (`cr_template_picker_button`,
// `consultation_note_field`, `ccam_picker`, `note_save_status`,
// `save_note_button`).
// Modes d'échec : aucun — `scrollable` suit la même logique que
// `CenterColumn` (pas de double scroll imbriqué en layout 1 colonne).
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../ccam_picker.dart';
import 'consultation_format_utils.dart';

/// Colonne « Saisie + note » (376 px) — recherche/ajout d'acte CCAM et note
/// de séance. `scrollable` suit la même logique que `CenterColumn`.
class SideColumn extends StatelessWidget {
  const SideColumn({
    super.key,
    required this.textTheme,
    required this.noteController,
    required this.onPickCrTemplate,
    required this.onNoteChanged,
    required this.lastNoteSavedAt,
    required this.selectedTooth,
    required this.onClearSelectedTooth,
    required this.onActSubmitted,
    required this.scrollable,
    required this.actSearchFocusNode,
  });

  final TextTheme textTheme;
  final TextEditingController noteController;
  final VoidCallback onPickCrTemplate;
  final ValueChanged<String> onNoteChanged;
  final DateTime? lastNoteSavedAt;
  final String? selectedTooth;
  // #4959 — efface la dent sélectionnée depuis la croix de la pastille en
  // tête du panneau « Ajouter un acte ».
  final VoidCallback onClearSelectedTooth;
  // #4948 — focus partagé avec la recherche globale de la barre du haut.
  final FocusNode actSearchFocusNode;
  final void Function({
    required String code,
    required String label,
    String? tooth,
    required int amountCents,
  }) onActSubmitted;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: NubiaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'Note de séance',
                        style: textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('cr_template_picker_button'),
                      onPressed: onPickCrTemplate,
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: const Text('Modèle'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('consultation_note_field'),
                  controller: noteController,
                  maxLines: 4,
                  onChanged: onNoteChanged,
                  decoration: const InputDecoration(
                    hintText: 'Observations cliniques...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                _NoteSaveStatus(lastSavedAt: lastNoteSavedAt),
              ],
            ),
          ),
        ),
        // #4959 — pastille « Dent NN sélectionnée » en tête du panneau
        // « Ajouter un acte », visible uniquement si une dent est
        // sélectionnée (#4048, schéma dentaire).
        if (selectedTooth != null)
          _SelectedToothPill(
            tooth: selectedTooth!,
            onClear: onClearSelectedTooth,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: CcamPicker(
            key: const Key('ccam_picker'),
            useCase: GetIt.instance<GetActsUseCase>(),
            favoritesUseCase: GetIt.instance<FavoriteActsUseCase>(),
            // #4048 — la dent choisie via le schéma dentaire pré-remplit
            // l'éditeur d'acte au lieu de la saisie texte libre.
            selectedTooth: selectedTooth,
            onActSubmitted: onActSubmitted,
            // #4948 — focus partagé avec la recherche globale de la barre
            // du haut (et le raccourci ⌘K, #4941).
            searchFocusNode: actSearchFocusNode,
          ),
        ),
      ],
    );
    return scrollable ? SingleChildScrollView(child: content) : content;
  }
}

/// Pastille « Dent NN sélectionnée » (#4959, point 2 de la maquette) — rappelle
/// la dent choisie via le schéma dentaire (#4048) avant l'ajout d'un acte, et
/// permet de l'effacer via la croix (`act_tooth_picker_clear`, clé
/// conservée pour les tests de retrait de dent).
class _SelectedToothPill extends StatelessWidget {
  const _SelectedToothPill({required this.tooth, required this.onClear});

  final String tooth;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      key: const Key('selected_tooth_pill'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: NubiaColors.brand50,
        border: Border.all(color: NubiaColors.brand200),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.medical_services,
            size: 18,
            color: NubiaColors.brand600,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Dent $tooth sélectionnée',
              style: textTheme.labelMedium?.copyWith(
                color: NubiaColors.brand800,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            key: const Key('act_tooth_picker_clear'),
            onPressed: onClear,
            icon: const Icon(Icons.close, size: 18),
            color: NubiaColors.brand800,
            tooltip: 'Effacer la dent sélectionnée',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

/// Indicateur d'état de l'auto-save de la note de séance (#4943, #4963) —
/// remplace le bouton « Enregistrer la note » : icône `cloud_done` + horaire
/// du dernier enregistrement réussi, rien tant qu'aucun enregistrement n'a
/// encore eu lieu. La Key `save_note_button` (conservée depuis le bouton
/// manuel disparu) marque cet élément comme le déclencheur/état de l'auto-save
/// pour ne pas casser les tests existants. Le badge ⌘S rappelle le raccourci
/// manuel — son déclenchement effectif est traité par un ticket dédié.
class _NoteSaveStatus extends StatelessWidget {
  const _NoteSaveStatus({required this.lastSavedAt});

  final DateTime? lastSavedAt;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final savedAt = lastSavedAt;
    return Row(
      key: const Key('save_note_button'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (savedAt != null)
          Row(
            key: const Key('note_save_status'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_done, size: 16, color: tokens.successFg),
              const SizedBox(width: 4),
              Text(
                'Enregistré automatiquement à ${formatTime(savedAt)}',
                style: textTheme.bodySmall?.copyWith(color: tokens.successFg),
              ),
            ],
          )
        else
          const SizedBox.shrink(),
        const NubiaBadge.label(label: '⌘S'),
      ],
    );
  }
}
