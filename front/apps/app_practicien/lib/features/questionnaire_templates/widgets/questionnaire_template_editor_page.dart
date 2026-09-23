import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'question_draft.dart';
import 'question_editor_tile.dart';

/// Résultat renvoyé par [showQuestionnaireTemplateEditor] à l'enregistrement.
typedef QuestionnaireTemplateFormResult = ({
  String title,
  List<QuestionnaireQuestion> schema,
});

/// Édition du schéma d'un modèle de questionnaire du cabinet (#7158) :
/// ajout/suppression de questions, type, options, condition « afficher si »,
/// aperçu en direct. `initial` fourni = édition (questions pré-remplies) ;
/// `null` = création. Poussé en pleine page (pas un dialog) : la liste de
/// questions + l'aperçu demandent trop de place pour un `AlertDialog`.
Future<QuestionnaireTemplateFormResult?> showQuestionnaireTemplateEditor(
  BuildContext context, {
  QuestionnaireTemplate? initial,
}) {
  return Navigator.of(context).push<QuestionnaireTemplateFormResult>(
    MaterialPageRoute(
      builder: (_) => QuestionnaireTemplateEditorPage(initial: initial),
    ),
  );
}

class QuestionnaireTemplateEditorPage extends StatefulWidget {
  const QuestionnaireTemplateEditorPage({super.key, this.initial});

  final QuestionnaireTemplate? initial;

  @override
  State<QuestionnaireTemplateEditorPage> createState() =>
      _QuestionnaireTemplateEditorPageState();
}

class _QuestionnaireTemplateEditorPageState
    extends State<QuestionnaireTemplateEditorPage> {
  late final _title = TextEditingController(text: widget.initial?.title);
  late final List<QuestionDraft> _questions = [
    for (final question in widget.initial?.schema ?? const [])
      QuestionDraft.fromDomain(_nextId++, question),
  ];
  int _nextId = 0;
  final Map<String, dynamic> _previewValues = {};

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool get _titleValid => _title.text.trim().isNotEmpty;

  bool get _keysUnique {
    final keys = _questions.map((q) => q.key.trim()).toList();
    return keys.toSet().length == keys.length;
  }

  bool get _valid =>
      _titleValid &&
      _questions.isNotEmpty &&
      _questions.every((q) => q.isValid) &&
      _keysUnique;

  List<String> _availableConditionKeysBefore(int index) => [
        for (var i = 0; i < index; i++)
          if (_questions[i].type == QuestionnaireQuestionType.boolean &&
              _questions[i].key.trim().isNotEmpty)
            _questions[i].key.trim(),
      ];

  /// Questions valides converties en domaine, en écartant toute condition
  /// devenue obsolète (la question booléenne référencée a été renommée ou
  /// supprimée depuis) — l'API rejetterait sinon le schéma entier (422
  /// dangling condition).
  List<QuestionnaireQuestion> get _resolvedQuestions {
    final result = <QuestionnaireQuestion>[];
    for (var i = 0; i < _questions.length; i++) {
      final draft = _questions[i];
      if (!draft.isValid) continue;
      final available = _availableConditionKeysBefore(i);
      final conditionKey =
          available.contains(draft.conditionKey) ? draft.conditionKey : null;
      result.add(QuestionnaireQuestion(
        key: draft.key.trim(),
        type: draft.type,
        label: draft.label,
        options:
            draft.type == QuestionnaireQuestionType.select ? draft.options : const [],
        condition: conditionKey != null
            ? QuestionnaireCondition(key: conditionKey, equals: true)
            : null,
        required: draft.required,
        safetyFlag: draft.safetyFlag,
      ));
    }
    return result;
  }

  List<NubiaQuestionnaireFieldSpec> get _previewFields => _resolvedQuestions
      .where((question) => question.isVisible(_previewValues))
      .map((question) => NubiaQuestionnaireFieldSpec(
            key: question.key,
            type: switch (question.type) {
              QuestionnaireQuestionType.text =>
                NubiaQuestionnaireFieldType.text,
              QuestionnaireQuestionType.boolean =>
                NubiaQuestionnaireFieldType.boolean,
              QuestionnaireQuestionType.select =>
                NubiaQuestionnaireFieldType.select,
            },
            label: question.label,
            options: question.options,
            required: question.required,
            highlighted: question.safetyFlag,
          ))
      .toList();

  void _addQuestion() => setState(() => _questions.add(QuestionDraft(id: _nextId++)));

  void _removeQuestion(QuestionDraft draft) =>
      setState(() => _questions.remove(draft));

  void _onSave() {
    Navigator.of(context).pop((
      title: _title.text.trim(),
      schema: _resolvedQuestions,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return Scaffold(
      key: const Key('questionnaire_template_editor_scaffold'),
      appBar: AppBar(
        title: Text(editing ? 'Modifier le modèle' : 'Nouveau modèle'),
        actions: [
          TextButton(
            key: const Key('questionnaire_template_editor_save'),
            onPressed: _valid ? _onSave : null,
            child: const Text('Enregistrer'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NubiaTextField(
              key: const Key('questionnaire_template_editor_title'),
              controller: _title,
              label: 'Titre du questionnaire',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            Text('Questions', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (var i = 0; i < _questions.length; i++) ...[
              QuestionEditorTile(
                key: ValueKey(_questions[i].id),
                draft: _questions[i],
                availableConditionKeys: _availableConditionKeysBefore(i),
                onChanged: () => setState(() {}),
                onRemove: () => _removeQuestion(_questions[i]),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              key: const Key('questionnaire_template_editor_add_question'),
              onPressed: _addQuestion,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une question'),
            ),
            const SizedBox(height: 24),
            Text('Aperçu', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Container(
              key: const Key('questionnaire_template_editor_preview'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _previewFields.isEmpty
                  ? const Text('Ajoutez des questions pour voir l\'aperçu.')
                  : NubiaDynamicQuestionnaireForm(
                      fields: _previewFields,
                      values: _previewValues,
                      onChanged: (key, value) =>
                          setState(() => _previewValues[key] = value),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
