import 'package:flutter/material.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'questionnaire_template_tile.dart';

/// Corps de l'écran une fois les modèles chargés : le modèle du cabinet
/// (au plus un, éditable) puis le catalogue global (lecture seule) (#7158).
class QuestionnaireTemplatesList extends StatelessWidget {
  const QuestionnaireTemplatesList({
    super.key,
    required this.cabinetTemplate,
    required this.globalTemplates,
    required this.onEditCabinetTemplate,
    required this.onCreateCabinetTemplate,
  });

  final QuestionnaireTemplate? cabinetTemplate;
  final List<QuestionnaireTemplate> globalTemplates;
  final ValueChanged<QuestionnaireTemplate> onEditCabinetTemplate;
  final VoidCallback onCreateCabinetTemplate;

  @override
  Widget build(BuildContext context) {
    final cabinetTemplate = this.cabinetTemplate;
    return ListView(
      key: const Key('questionnaire_templates_list'),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Votre modèle', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (cabinetTemplate == null)
          Padding(
            key: const Key('questionnaire_templates_cabinet_empty'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Aucun modèle propre au cabinet — le questionnaire '
                  'standard ci-dessous est utilisé par défaut.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('questionnaire_templates_create_button'),
                  onPressed: onCreateCabinetTemplate,
                  icon: const Icon(Icons.add),
                  label: const Text('Créer mon propre modèle'),
                ),
              ],
            ),
          )
        else
          QuestionnaireTemplateTile(
            template: cabinetTemplate,
            onEdit: () => onEditCabinetTemplate(cabinetTemplate),
          ),
        const SizedBox(height: 24),
        Text('Catalogue standard', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final template in globalTemplates)
          QuestionnaireTemplateTile(template: template),
      ],
    );
  }
}
