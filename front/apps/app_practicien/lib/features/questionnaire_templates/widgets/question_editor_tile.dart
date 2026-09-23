import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'question_draft.dart';

/// Une question du schéma en cours d'édition : type, libellé, options (si
/// `select`), condition « afficher si », requis, signalement (#7158). Mute
/// [draft] en place puis notifie [onChanged] — pas de rebuild de ce widget
/// depuis l'extérieur (identité stable via `ValueKey(draft.id)` dans la
/// liste parente), donc les contrôleurs texte ne perdent jamais le focus.
class QuestionEditorTile extends StatefulWidget {
  const QuestionEditorTile({
    super.key,
    required this.draft,
    required this.availableConditionKeys,
    required this.onChanged,
    required this.onRemove,
  });

  final QuestionDraft draft;

  /// Clés des questions booléennes déjà définies avant celle-ci dans le
  /// schéma — seules candidates pour la condition « afficher si ».
  final List<String> availableConditionKeys;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<QuestionEditorTile> createState() => _QuestionEditorTileState();
}

/// Valeur factice représentant « aucune condition » dans le sélecteur —
/// [QuestionDraft.conditionKey] reste `null` en interne, cette chaîne
/// n'existe que pour permettre au praticien de revenir à « toujours
/// affichée » depuis la feuille de sélection.
const _noConditionValue = '__none__';

class _QuestionEditorTileState extends State<QuestionEditorTile> {
  late final _key = TextEditingController(text: widget.draft.key);
  late final _label = TextEditingController(text: widget.draft.label);
  late final _options =
      TextEditingController(text: widget.draft.options.join(', '));

  @override
  void dispose() {
    _key.dispose();
    _label.dispose();
    _options.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return NubiaCard(
      key: Key('question_editor_tile_${draft.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: NubiaTextField(
                    key: Key('question_editor_key_${draft.id}'),
                    controller: _key,
                    label: 'Clé (identifiant technique)',
                    hint: 'ex. antecedents',
                    onChanged: (value) {
                      draft.key = value.trim();
                      widget.onChanged();
                    },
                  ),
                ),
                IconButton(
                  key: Key('question_editor_remove_${draft.id}'),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Supprimer cette question',
                  onPressed: widget.onRemove,
                ),
              ],
            ),
            const SizedBox(height: 12),
            NubiaTextField(
              key: Key('question_editor_label_${draft.id}'),
              controller: _label,
              label: 'Libellé affiché au patient',
              onChanged: (value) {
                draft.label = value;
                widget.onChanged();
              },
            ),
            const SizedBox(height: 12),
            NubiaSelect<QuestionnaireQuestionType>(
              key: Key('question_editor_type_${draft.id}'),
              label: 'Type de réponse',
              value: draft.type,
              items: const [
                NubiaSelectItem(
                  value: QuestionnaireQuestionType.text,
                  label: 'Texte libre',
                ),
                NubiaSelectItem(
                  value: QuestionnaireQuestionType.boolean,
                  label: 'Oui / Non',
                ),
                NubiaSelectItem(
                  value: QuestionnaireQuestionType.select,
                  label: 'Choix parmi une liste',
                ),
              ],
              onChanged: (value) {
                setState(() => draft.type = value);
                widget.onChanged();
              },
            ),
            if (draft.type == QuestionnaireQuestionType.select) ...[
              const SizedBox(height: 12),
              NubiaTextField(
                key: Key('question_editor_options_${draft.id}'),
                controller: _options,
                label: 'Options (séparées par des virgules)',
                hint: 'ex. Type 1, Type 2',
                onChanged: (value) {
                  draft.options = value
                      .split(',')
                      .map((o) => o.trim())
                      .where((o) => o.isNotEmpty)
                      .toList();
                  widget.onChanged();
                },
              ),
            ],
            const SizedBox(height: 12),
            NubiaSelect<String>(
              key: Key('question_editor_condition_${draft.id}'),
              label: 'Afficher si (question oui/non précédente)',
              value: draft.conditionKey ?? _noConditionValue,
              items: [
                const NubiaSelectItem(
                  value: _noConditionValue,
                  label: 'Toujours affichée',
                ),
                for (final conditionKey in widget.availableConditionKeys)
                  NubiaSelectItem(value: conditionKey, label: conditionKey),
              ],
              onChanged: (value) {
                setState(() {
                  draft.conditionKey =
                      value == _noConditionValue ? null : value;
                });
                widget.onChanged();
              },
            ),
            const SizedBox(height: 8),
            NubiaCheckbox(
              key: Key('question_editor_required_${draft.id}'),
              value: draft.required,
              label: 'Réponse obligatoire',
              onChanged: (value) {
                setState(() => draft.required = value);
                widget.onChanged();
              },
            ),
            NubiaCheckbox(
              key: Key('question_editor_safety_flag_${draft.id}'),
              value: draft.safetyFlag,
              label: "Signaler à l'attention du praticien",
              onChanged: (value) {
                setState(() => draft.safetyFlag = value);
                widget.onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}
