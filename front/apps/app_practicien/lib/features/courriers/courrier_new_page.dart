import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'letter_compose_cubit.dart';
import 'letter_compose_state.dart';
import 'widgets/letter_preview_card.dart';

/// Libellés français des placeholders connus (`KNOWN_PLACEHOLDERS`,
/// `api/src/letters.rs`) — `correspondant.nom` est le seul jamais résolu côté
/// serveur (aucune entité correspondant côté cabinet, #7197) : c'est le champ
/// libre attendu par le procédé « choix du correspondant » de cet écran.
const _kPlaceholderLabels = <String, String>{
  'patient.prenom': 'Prénom du patient',
  'patient.nom': 'Nom du patient',
  'patient.date_naissance': 'Date de naissance du patient',
  'cabinet.nom': 'Nom du cabinet',
  'cabinet.adresse': 'Adresse du cabinet',
  'cabinet.telephone': 'Téléphone du cabinet',
  'praticien.nom': 'Nom du praticien',
  'praticien.rpps': 'RPPS du praticien',
  'rdv.date': 'Date du rendez-vous',
  'rdv.heure': 'Heure du rendez-vous',
  'date.aujourdhui': 'Date du jour',
  'correspondant.nom': 'Correspondant',
};

final _placeholderPattern = RegExp(r'\{\{\s*([\w.]+)\s*\}\}');

/// Substitution locale, best-effort (cf. `LetterPreviewCard`) : un
/// placeholder sans valeur connue reste visible entre crochets plutôt que de
/// disparaître silencieusement.
String _renderPreview(String template, Map<String, String> values) {
  return template.replaceAllMapped(_placeholderPattern, (match) {
    final key = match.group(1)!;
    final value = values[key]?.trim();
    return (value != null && value.isNotEmpty) ? value : '[$key]';
  });
}

String _formatDate(DateTime dt) {
  final d = dt.toLocal();
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd/$mm/${d.year}';
}

/// Composition d'un courrier depuis la fiche patient (`/patients/:id/courrier`,
/// #7196) : choix du modèle (#7197), champs libres pour les placeholders,
/// aperçu, génération PDF + ajout aux documents du patient.
class CourrierNewPage extends StatelessWidget {
  const CourrierNewPage({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<LetterComposeCubit>()..load(patientId),
      child: CourrierComposeBody(patientId: patientId),
    );
  }
}

class CourrierComposeBody extends StatelessWidget {
  const CourrierComposeBody({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LetterComposeCubit, LetterComposeState>(
      listener: (context, state) {
        if (state is LetterComposeReady && state.error != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.error!)));
        }
      },
      builder: (context, state) {
        return switch (state) {
          LetterComposeLoading() => const Center(
              key: Key('courrier_loading'),
              child: CircularProgressIndicator(),
            ),
          LetterComposeError(:final message) => NubiaErrorWidget(
              key: const Key('courrier_error'),
              message: message,
              onRetry: () => context.read<LetterComposeCubit>().load(patientId),
            ),
          LetterComposeReady() => _ComposeForm(
              patientId: patientId,
              templates: state.templates,
              patient: state.patient,
              submitting: state.submitting,
            ),
          LetterComposeGenerated(:final letter) =>
            _GeneratedConfirmation(patientId: patientId, letter: letter),
        };
      },
    );
  }
}

class _ComposeForm extends StatefulWidget {
  const _ComposeForm({
    required this.patientId,
    required this.templates,
    required this.patient,
    required this.submitting,
  });

  final String patientId;
  final List<LetterTemplate> templates;
  final CabinetPatient? patient;
  final bool submitting;

  @override
  State<_ComposeForm> createState() => _ComposeFormState();
}

class _ComposeFormState extends State<_ComposeForm> {
  String? _selectedTemplateId;
  final Map<String, TextEditingController> _overrideControllers = {};

  LetterTemplate? get _selectedTemplate {
    final id = _selectedTemplateId;
    if (id == null) return null;
    for (final template in widget.templates) {
      if (template.id == id) return template;
    }
    return null;
  }

  void _selectTemplate(LetterTemplate template) {
    setState(() {
      _selectedTemplateId = template.id;
      for (final controller in _overrideControllers.values) {
        controller.dispose();
      }
      _overrideControllers.clear();
      for (final placeholder in template.placeholders) {
        _overrideControllers[placeholder] = TextEditingController();
      }
    });
  }

  Map<String, String> _knownValues() {
    final patient = widget.patient;
    return {
      if (patient != null) 'patient.prenom': patient.firstName,
      if (patient != null) 'patient.nom': patient.lastName,
      if (patient?.birthDate != null)
        'patient.date_naissance': _formatDate(patient!.birthDate!),
      'date.aujourdhui': _formatDate(DateTime.now()),
      for (final entry in _overrideControllers.entries)
        entry.key: entry.value.text,
    };
  }

  void _submit() {
    final template = _selectedTemplate;
    if (template == null) return;
    final overrides = <String, String>{
      for (final entry in _overrideControllers.entries)
        if (entry.value.text.trim().isNotEmpty)
          entry.key: entry.value.text.trim(),
    };
    context.read<LetterComposeCubit>().generate(
          widget.patientId,
          templateId: template.id,
          overrides: overrides,
        );
  }

  @override
  void dispose() {
    for (final controller in _overrideControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final template = _selectedTemplate;
    final patientName =
        widget.patient != null && widget.patient!.fullName.isNotEmpty
            ? widget.patient!.fullName
            : 'Patient';

    return SingleChildScrollView(
      key: const Key('courrier_form'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Courrier pour $patientName',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          _TemplatePicker(
            templates: widget.templates,
            selectedTemplateId: _selectedTemplateId,
            onSelected: _selectTemplate,
          ),
          if (template != null) ...[
            const SizedBox(height: 20),
            _OverrideFields(
              placeholders: template.placeholders,
              controllers: _overrideControllers,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 20),
            LetterPreviewCard(
              templateName: template.name,
              renderedBody:
                  _renderPreview(template.bodyTemplate, _knownValues()),
            ),
          ],
          const SizedBox(height: 24),
          NubiaButton(
            key: const Key('submit_courrier_button'),
            label: 'Générer et ajouter aux documents',
            isLoading: widget.submitting,
            onPressed: (template == null || widget.submitting) ? null : _submit,
          ),
        ],
      ),
    );
  }
}

/// Choix du modèle (#7197) — cartes tactiles, même pattern que
/// `_TemplateSection` (`ordonnance_new_page.dart`).
class _TemplatePicker extends StatelessWidget {
  const _TemplatePicker({
    required this.templates,
    required this.selectedTemplateId,
    required this.onSelected,
  });

  final List<LetterTemplate> templates;
  final String? selectedTemplateId;
  final ValueChanged<LetterTemplate> onSelected;

  @override
  Widget build(BuildContext context) {
    if (templates.isEmpty) {
      return const NubiaEmptyState(
        key: Key('courrier_templates_empty'),
        icon: Icons.mail_outlined,
        title: 'Aucun modèle de courrier',
        subtitle: 'Créez un modèle de courrier pour pouvoir en rédiger un.',
      );
    }
    return NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Modèle', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final template in templates)
                NubiaChip(
                  key: Key('courrier_template_${template.id}'),
                  label: template.name,
                  variant: NubiaChipVariant.choice,
                  selected: template.id == selectedTemplateId,
                  onTap: () => onSelected(template),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Champs libres, un par placeholder du modèle choisi (#7196) —
/// `correspondant.nom` (aucune valeur automatique côté serveur, #7197) comme
/// tout autre placeholder resté sans valeur : laissé vide, il retombe sur
/// l'erreur serveur `missing_placeholder_values` plutôt que de bloquer la
/// saisie ici.
class _OverrideFields extends StatelessWidget {
  const _OverrideFields({
    required this.placeholders,
    required this.controllers,
    required this.onChanged,
  });

  final List<String> placeholders;
  final Map<String, TextEditingController> controllers;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    if (placeholders.isEmpty) return const SizedBox.shrink();
    return NubiaCard(
      key: const Key('courrier_override_fields'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Champs du courrier',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          for (final placeholder in placeholders) ...[
            NubiaTextField(
              key: Key('courrier_field_$placeholder'),
              controller: controllers[placeholder],
              label: _kPlaceholderLabels[placeholder] ?? placeholder,
              hint: placeholder == 'correspondant.nom'
                  ? 'Nom du confrère ou de l\'organisme destinataire'
                  : 'Laissez vide pour un remplissage automatique',
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _GeneratedConfirmation extends StatelessWidget {
  const _GeneratedConfirmation({required this.patientId, required this.letter});

  final String patientId;
  final GeneratedLetter letter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = theme.extension<NubiaTokens>()!;

    return Center(
      key: const Key('courrier_generated_confirmation'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: tokens.successBg,
                shape: BoxShape.circle,
              ),
              child:
                  Icon(Icons.check_rounded, size: 48, color: tokens.successFg),
            ),
            const SizedBox(height: 20),
            Text(
              'Courrier généré',
              style: theme.textTheme.titleLarge?.copyWith(color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              '${letter.filename} ajouté aux documents du patient.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            NubiaButton(
              key: const Key('back_to_patient_button'),
              label: 'Retour à la fiche patient',
              onPressed: () => context.go('/patients/$patientId'),
            ),
          ],
        ),
      ),
    );
  }
}
