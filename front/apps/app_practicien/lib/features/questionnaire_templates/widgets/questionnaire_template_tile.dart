import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Une ligne de la liste des modèles de questionnaire : titre + version,
/// dépliable pour l'aperçu complet du schéma, éditable si propre au cabinet
/// (#7158).
class QuestionnaireTemplateTile extends StatelessWidget {
  const QuestionnaireTemplateTile({
    super.key,
    required this.template,
    this.onEdit,
  });

  final QuestionnaireTemplate template;

  /// `null` : modèle du catalogue global, lecture seule (pas de bouton
  /// « Modifier »).
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return NubiaCard(
      key: Key('questionnaire_template_${template.id}'),
      child: ExpansionTile(
        title: Text(template.title),
        subtitle: Text('v${template.version} · ${template.schema.length} question(s)'),
        trailing: onEdit == null
            ? null
            : IconButton(
                key: Key('questionnaire_template_edit_${template.id}'),
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Modifier',
                onPressed: onEdit,
              ),
        children: [
          Padding(
            key: Key('questionnaire_template_preview_${template.id}'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: NubiaDynamicQuestionnaireForm(
              fields: [
                for (final question in template.schema)
                  NubiaQuestionnaireFieldSpec(
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
                  ),
              ],
              values: const {},
              readOnly: true,
            ),
          ),
        ],
      ),
    );
  }
}
