//! Écran de saisie du questionnaire médical patient (#4109) — rendu
//! dynamique piloté par le schéma actif du cabinet (#7158), types de
//! questions, options, condition « afficher si ». Proposé avant le prochain
//! RDV (accessible depuis `mes_rdv_page.dart`, qui fournit le `cabinetId`).
//! Précharge la soumission existante (#4459) ; en lecture seule si elle a
//! déjà été transmise au cabinet (le `PATCH` n'accepte que les brouillons).

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'medical_questionnaire_cubit.dart';

class MedicalQuestionnairePage extends StatelessWidget {
  const MedicalQuestionnairePage({super.key, required this.cabinetId});

  final String cabinetId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => MedicalQuestionnaireCubit(
        cabinetId: cabinetId,
        create: GetIt.instance<CreateMedicalQuestionnaireUseCase>(),
        patch: GetIt.instance<PatchMedicalQuestionnaireUseCase>(),
        get: GetIt.instance<GetMedicalQuestionnaireUseCase>(),
        getActiveTemplate:
            GetIt.instance<GetActiveMedicalQuestionnaireTemplateUseCase>(),
      ),
      child: const _MedicalQuestionnaireBody(),
    );
  }
}

class _MedicalQuestionnaireBody extends StatefulWidget {
  const _MedicalQuestionnaireBody();

  @override
  State<_MedicalQuestionnaireBody> createState() =>
      _MedicalQuestionnaireBodyState();
}

class _MedicalQuestionnaireBodyState extends State<_MedicalQuestionnaireBody> {
  QuestionnaireTemplate? _template;
  Map<String, dynamic> _values = {};

  /// `true` tant que le chargement initial (#4459) n'a pas rendu son
  /// premier résultat — évite d'afficher brièvement un formulaire vierge
  /// éditable avant qu'une soumission existante ne soit préchargée.
  bool _initialLoading = true;

  /// `true` si une soumission non-brouillon existe déjà : le patient peut la
  /// relire mais pas la modifier (`PATCH` n'accepte que les brouillons).
  bool _readOnly = false;
  DateTime? _submittedAt;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Questionnaire médical')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: BlocConsumer<MedicalQuestionnaireCubit,
              MedicalQuestionnaireState>(
            listener: (context, state) {
              if (state is MedicalQuestionnaireLoaded) {
                setState(() {
                  _template = state.template;
                  _values = Map<String, dynamic>.from(
                    state.questionnaire?.payload ?? const {},
                  );
                  _readOnly = state.questionnaire != null &&
                      state.questionnaire!.status != 'draft';
                  _submittedAt = state.questionnaire?.submittedAt;
                  _initialLoading = false;
                });
              }
              if (state is MedicalQuestionnaireSaved) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Brouillon enregistré')),
                );
              }
              if (state is MedicalQuestionnaireSubmitted) {
                context.pop();
              }
              // Le chargement initial du schéma actif a échoué (cabinet
              // introuvable, erreur réseau…) : il n'y a rien à construire,
              // sortir de l'état « chargement » pour laisser le builder
              // afficher la bannière d'erreur plutôt qu'un spinner infini.
              if (state is MedicalQuestionnaireError && _initialLoading) {
                setState(() => _initialLoading = false);
              }
            },
            builder: (context, state) {
              if (_initialLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              final template = _template;
              if (template == null) {
                final message = state is MedicalQuestionnaireError
                    ? state.message
                    : 'Impossible de charger le questionnaire.';
                return Container(
                  key: const Key('medical_questionnaire_error_banner'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                );
              }
              final loading = state is MedicalQuestionnaireSaving;
              final fieldsEnabled = !loading && !_readOnly;
              final visibleQuestions = template.schema
                  .where((question) => question.isVisible(_values))
                  .toList();
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      template.title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ces informations aident votre praticien à préparer '
                      'votre consultation.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (_readOnly) ...[
                      const SizedBox(height: 16),
                      Container(
                        key: const Key('medical_questionnaire_readonly_banner'),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _submittedAt != null
                              ? 'Déjà transmis à votre cabinet le '
                                  '${_submittedAt!.day.toString().padLeft(2, '0')}/'
                                  '${_submittedAt!.month.toString().padLeft(2, '0')}/'
                                  '${_submittedAt!.year}.'
                              : 'Déjà transmis à votre cabinet.',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                    if (state is MedicalQuestionnaireError) ...[
                      const SizedBox(height: 16),
                      Container(
                        key: const Key('medical_questionnaire_error_banner'),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          state.message,
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    NubiaDynamicQuestionnaireForm(
                      key: const Key('medical_questionnaire_form'),
                      fields: visibleQuestions.map(_toFieldSpec).toList(),
                      values: _values,
                      readOnly: !fieldsEnabled,
                      onChanged: fieldsEnabled
                          ? (key, value) =>
                              setState(() => _values[key] = value)
                          : null,
                    ),
                    if (!_readOnly) ...[
                      const SizedBox(height: 8),
                      NubiaButton(
                        key: const Key('medical_questionnaire_submit_button'),
                        label: 'Envoyer au cabinet',
                        isLoading: loading,
                        onPressed: loading
                            ? null
                            : () => context
                                .read<MedicalQuestionnaireCubit>()
                                .submit(_values),
                      ),
                      const SizedBox(height: 12),
                      NubiaButton(
                        key: const Key(
                            'medical_questionnaire_save_draft_button'),
                        label: 'Enregistrer le brouillon',
                        variant: NubiaButtonVariant.secondary,
                        onPressed: loading
                            ? null
                            : () => context
                                .read<MedicalQuestionnaireCubit>()
                                .saveDraft(_values),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  NubiaQuestionnaireFieldSpec _toFieldSpec(QuestionnaireQuestion question) =>
      NubiaQuestionnaireFieldSpec(
        key: question.key,
        type: switch (question.type) {
          QuestionnaireQuestionType.text => NubiaQuestionnaireFieldType.text,
          QuestionnaireQuestionType.boolean =>
            NubiaQuestionnaireFieldType.boolean,
          QuestionnaireQuestionType.select =>
            NubiaQuestionnaireFieldType.select,
        },
        label: question.label,
        options: question.options,
        required: question.required,
        highlighted: question.safetyFlag,
      );
}
