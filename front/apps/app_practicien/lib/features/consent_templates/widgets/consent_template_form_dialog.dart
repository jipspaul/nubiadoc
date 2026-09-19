import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../consent_act_categories.dart';

/// Résultat renvoyé par [showConsentTemplateFormDialog] à la validation.
typedef ConsentTemplateFormResult = ({
  String actCategory,
  String title,
  String bodyMarkdown,
});

/// Formulaire de création/édition d'un modèle de consentement du cabinet
/// (#7198, DP-F6.c). `initial` fourni = édition (champs pré-remplis) ; `null`
/// = création. Inclut un aperçu texte du corps saisi.
Future<ConsentTemplateFormResult?> showConsentTemplateFormDialog(
  BuildContext context, {
  ConsentTemplate? initial,
}) {
  return showDialog<ConsentTemplateFormResult>(
    context: context,
    builder: (_) => ConsentTemplateFormDialog(initial: initial),
  );
}

class ConsentTemplateFormDialog extends StatefulWidget {
  const ConsentTemplateFormDialog({super.key, this.initial});

  final ConsentTemplate? initial;

  @override
  State<ConsentTemplateFormDialog> createState() =>
      _ConsentTemplateFormDialogState();
}

class _ConsentTemplateFormDialogState
    extends State<ConsentTemplateFormDialog> {
  late final _title = TextEditingController(text: widget.initial?.title);
  late final _body =
      TextEditingController(text: widget.initial?.bodyMarkdown);
  late String? _actCategory = widget.initial?.actCategory;

  bool get _valid =>
      _actCategory != null &&
      _title.text.trim().isNotEmpty &&
      _body.text.trim().isNotEmpty;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return AlertDialog(
      title: Text(editing ? 'Modifier le modèle' : 'Nouveau modèle'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              NubiaSelect<String>(
                key: const Key('consent_template_category_field'),
                label: "Type d'acte",
                value: _actCategory,
                items: [
                  for (final entry in consentActCategories.entries)
                    NubiaSelectItem(value: entry.key, label: entry.value),
                ],
                onChanged: (value) => setState(() => _actCategory = value),
              ),
              const SizedBox(height: 12),
              NubiaTextField(
                key: const Key('consent_template_title_field'),
                controller: _title,
                label: 'Titre',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              NubiaTextField(
                key: const Key('consent_template_body_field'),
                controller: _body,
                label: 'Texte (markdown)',
                maxLines: 8,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Text('Aperçu', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Container(
                key: const Key('consent_template_preview'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _body.text.trim().isEmpty
                      ? 'Le texte du modèle s\'affichera ici.'
                      : _body.text,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          key: const Key('consent_template_form_confirm'),
          onPressed: _valid ? _onConfirm : null,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }

  void _onConfirm() {
    final actCategory = _actCategory;
    if (actCategory == null) return;
    Navigator.of(context).pop((
      actCategory: actCategory,
      title: _title.text.trim(),
      bodyMarkdown: _body.text.trim(),
    ));
  }
}
