import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../ccam_picker.dart';
import '../../dental_chart/tooth_grid.dart';

/// Zone de saisie d'acte : sélection de dent (#4048) + recherche/favoris
/// CCAM. La dent choisie pré-remplit l'éditeur d'acte.
///
/// L'état `selectedTooth` est porté par la vue parente (partagé avec le
/// futur odontogramme intégré du module dentaire, lot 3).
class ActEntryPanel extends StatelessWidget {
  const ActEntryPanel({
    super.key,
    required this.selectedTooth,
    required this.onToothSelected,
    required this.onToothCleared,
    required this.onActSubmitted,
  });

  final String? selectedTooth;
  final ValueChanged<String> onToothSelected;
  final VoidCallback onToothCleared;
  final void Function({
    required String code,
    required String label,
    String? tooth,
    required int amountCents,
  }) onActSubmitted;

  Future<void> _pickTooth(BuildContext context) async {
    final tooth = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: ToothGrid(
          quadrants: FdiQuadrants.permanent,
          keyPrefix: 'act_tooth_picker',
          colorFor: (code) => code == selectedTooth
              ? Theme.of(ctx).colorScheme.primary
              : Colors.grey.shade100,
          onTap: (code) => Navigator.of(ctx).pop(code),
        ),
      ),
    );
    if (tooth != null) {
      onToothSelected(tooth);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('act_entry_panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('act_tooth_picker_button'),
                  onPressed: () => _pickTooth(context),
                  icon: const Icon(Icons.grid_view_outlined, size: 18),
                  label: Text(
                    selectedTooth == null
                        ? 'Choisir une dent'
                        : 'Dent $selectedTooth',
                  ),
                ),
              ),
              if (selectedTooth != null)
                IconButton(
                  key: const Key('act_tooth_picker_clear'),
                  icon: const Icon(Icons.close),
                  tooltip: 'Retirer la dent sélectionnée',
                  onPressed: onToothCleared,
                ),
            ],
          ),
        ),
        CcamPicker(
          key: const Key('ccam_picker'),
          useCase: GetIt.instance<GetActsUseCase>(),
          favoritesUseCase: GetIt.instance<FavoriteActsUseCase>(),
          // #4048 — la dent choisie via le schéma dentaire pré-remplit
          // l'éditeur d'acte au lieu de la saisie texte libre.
          selectedTooth: selectedTooth,
          // #3402 — l'éditeur d'acte fournit la dent + le montant, transmis au
          // POST .../acts (le total reflète alors la somme des montants).
          onActSubmitted: onActSubmitted,
        ),
      ],
    );
  }
}
