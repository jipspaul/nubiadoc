import 'package:flutter/material.dart';
import 'package:nubia_design_system/src/widgets/nubia_badge.dart';
import 'package:nubia_design_system/src/widgets/nubia_select.dart';
import 'package:nubia_design_system/src/widgets/nubia_text_field.dart';

/// Type d'un champ de [NubiaDynamicQuestionnaireForm]. Standalone (le design
/// system ne dépend pas de `nubia_domain`) — c'est à l'appelant de mapper son
/// modèle de domaine (ex. `QuestionnaireQuestion`) vers [NubiaQuestionnaireFieldSpec].
enum NubiaQuestionnaireFieldType { text, boolean, select }

/// Description d'un champ à rendre, indépendante de tout schéma métier.
/// La visibilité conditionnelle (« afficher si ») est résolue par
/// l'appelant : [fields] ne doit contenir que les champs déjà visibles pour
/// les valeurs courantes.
class NubiaQuestionnaireFieldSpec {
  const NubiaQuestionnaireFieldSpec({
    required this.key,
    required this.type,
    required this.label,
    this.options = const [],
    this.required = false,
    this.highlighted = false,
  });

  final String key;
  final NubiaQuestionnaireFieldType type;
  final String label;

  /// Options proposées, uniquement pour [NubiaQuestionnaireFieldType.select].
  final List<String> options;
  final bool required;

  /// Affiche un badge d'attention (ex. `safetyFlag` métier) — pure
  /// annotation visuelle, sans effet sur la validation.
  final bool highlighted;
}

/// Rendu dynamique d'un questionnaire piloté par [fields] (#7158). Partagé
/// entre la saisie patient (`app_patient`) et l'aperçu praticien
/// (`app_practicien`) — un seul champ par [NubiaQuestionnaireFieldSpec], dans
/// l'ordre fourni.
class NubiaDynamicQuestionnaireForm extends StatefulWidget {
  const NubiaDynamicQuestionnaireForm({
    super.key,
    required this.fields,
    required this.values,
    this.onChanged,
    this.readOnly = false,
  });

  final List<NubiaQuestionnaireFieldSpec> fields;

  /// Réponses courantes, indexées par [NubiaQuestionnaireFieldSpec.key].
  final Map<String, dynamic> values;

  /// `null` : formulaire non éditable (aucun champ n'appelle ce callback,
  /// équivalent à [readOnly] pour les champs qui ne l'exposent pas déjà).
  final void Function(String key, dynamic value)? onChanged;
  final bool readOnly;

  @override
  State<NubiaDynamicQuestionnaireForm> createState() =>
      _NubiaDynamicQuestionnaireFormState();
}

class _NubiaDynamicQuestionnaireFormState
    extends State<NubiaDynamicQuestionnaireForm> {
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _createMissingControllers();
  }

  @override
  void didUpdateWidget(covariant NubiaDynamicQuestionnaireForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Une condition « afficher si » satisfaite entre deux builds peut révéler
    // un nouveau champ texte absent de `widget.fields` lors du premier
    // `initState` — il lui faut son propre contrôleur. Les champs déjà
    // connus ne sont jamais resynchronisés depuis `values` ensuite : ce
    // widget est monté avec les valeurs déjà chargées (l'appelant affiche un
    // spinner tant que le questionnaire initial n'est pas résolu), et
    // `onChanged` fait déjà remonter la saisie vers l'appelant.
    _createMissingControllers();
  }

  void _createMissingControllers() {
    for (final field in widget.fields) {
      if (field.type == NubiaQuestionnaireFieldType.text &&
          !_controllers.containsKey(field.key)) {
        _controllers[field.key] = TextEditingController(
          text: widget.values[field.key] as String? ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !widget.readOnly && widget.onChanged != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final field in widget.fields) ...[
          _buildLabel(context, field),
          const SizedBox(height: 4),
          _buildField(field, enabled: enabled),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildLabel(BuildContext context, NubiaQuestionnaireFieldSpec field) {
    if (field.type == NubiaQuestionnaireFieldType.boolean) {
      return const SizedBox.shrink();
    }
    if (!field.highlighted) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: NubiaBadge.label(label: 'Attention', variant: NubiaBadgeVariant.warning),
    );
  }

  Widget _buildField(NubiaQuestionnaireFieldSpec field, {required bool enabled}) {
    switch (field.type) {
      case NubiaQuestionnaireFieldType.text:
        return NubiaTextField(
          key: Key('questionnaire_field_${field.key}'),
          variant: NubiaTextFieldVariant.multiline,
          controller: _controllers[field.key],
          label: _fieldLabel(field),
          enabled: enabled,
          onChanged: enabled
              ? (value) => widget.onChanged!(field.key, value)
              : null,
        );
      case NubiaQuestionnaireFieldType.boolean:
        return SwitchListTile(
          key: Key('questionnaire_field_${field.key}'),
          contentPadding: EdgeInsets.zero,
          title: Row(
            children: [
              Expanded(child: Text(_fieldLabel(field))),
              if (field.highlighted) ...[
                const SizedBox(width: 8),
                const NubiaBadge.label(
                  label: 'Attention',
                  variant: NubiaBadgeVariant.warning,
                ),
              ],
            ],
          ),
          value: widget.values[field.key] as bool? ?? false,
          onChanged: enabled
              ? (value) => widget.onChanged!(field.key, value)
              : null,
        );
      case NubiaQuestionnaireFieldType.select:
        return NubiaSelect<String>(
          key: Key('questionnaire_field_${field.key}'),
          label: _fieldLabel(field),
          value: widget.values[field.key] as String?,
          items: [
            for (final option in field.options)
              NubiaSelectItem(value: option, label: option),
          ],
          onChanged: enabled
              ? (value) => widget.onChanged!(field.key, value)
              : null,
        );
    }
  }

  String _fieldLabel(NubiaQuestionnaireFieldSpec field) =>
      field.required ? '${field.label} *' : field.label;
}
