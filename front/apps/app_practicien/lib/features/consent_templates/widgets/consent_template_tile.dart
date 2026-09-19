import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../consent_act_categories.dart';

/// Une ligne de la liste des modèles de consentement : titre + type d'acte,
/// dépliable pour l'aperçu du texte, éditable si propre au cabinet.
class ConsentTemplateTile extends StatelessWidget {
  const ConsentTemplateTile({
    super.key,
    required this.template,
    this.onEdit,
  });

  final ConsentTemplate template;

  /// `null` : modèle du catalogue global, lecture seule (pas de bouton
  /// « Modifier »).
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return NubiaCard(
      key: Key('consent_template_${template.id}'),
      child: ExpansionTile(
        title: Text(template.title),
        subtitle: Text(
          '${consentActCategoryLabel(template.actCategory)} · v${template.version}',
        ),
        trailing: onEdit == null
            ? null
            : IconButton(
                key: Key('consent_template_edit_${template.id}'),
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Modifier',
                onPressed: onEdit,
              ),
        children: [
          Padding(
            key: Key('consent_template_preview_${template.id}'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(template.bodyMarkdown),
            ),
          ),
        ],
      ),
    );
  }
}
