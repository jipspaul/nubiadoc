import 'package:flutter/material.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'consent_template_tile.dart';

/// Corps de l'écran une fois les modèles chargés : section « cabinet »
/// (éditable) puis catalogue global (lecture seule).
class ConsentTemplatesList extends StatelessWidget {
  const ConsentTemplatesList({
    super.key,
    required this.templates,
    required this.onEdit,
  });

  final List<ConsentTemplate> templates;
  final ValueChanged<ConsentTemplate> onEdit;

  @override
  Widget build(BuildContext context) {
    final cabinet = templates.where((t) => !t.isGlobal).toList();
    final catalogue = templates.where((t) => t.isGlobal).toList();

    return ListView(
      key: const Key('consent_templates_list'),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Modèles du cabinet', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (cabinet.isEmpty)
          const Padding(
            key: Key('consent_templates_cabinet_empty'),
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Aucun modèle propre au cabinet pour le moment.'),
          )
        else
          for (final template in cabinet)
            ConsentTemplateTile(
              template: template,
              onEdit: () => onEdit(template),
            ),
        const SizedBox(height: 24),
        Text('Catalogue standard', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final template in catalogue) ConsentTemplateTile(template: template),
      ],
    );
  }
}
