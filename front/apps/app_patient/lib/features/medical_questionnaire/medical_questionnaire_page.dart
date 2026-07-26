//! Écran de saisie du questionnaire médical patient (#4109) — antécédents,
//! allergies, traitements en cours, ALD. Proposé avant le prochain RDV
//! (accessible depuis `mes_rdv_page.dart`, qui fournit le `cabinetId`).
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
  final _antecedents = TextEditingController();
  final _allergies = TextEditingController();
  final _traitements = TextEditingController();
  bool _ald = false;

  /// `true` tant que le chargement initial (#4459) n'a pas rendu son
  /// premier résultat — évite d'afficher brièvement un formulaire vierge
  /// éditable avant qu'une soumission existante ne soit préchargée.
  bool _initialLoading = true;

  /// `true` si une soumission non-brouillon existe déjà : le patient peut la
  /// relire mais pas la modifier (`PATCH` n'accepte que les brouillons).
  bool _readOnly = false;
  DateTime? _submittedAt;

  @override
  void dispose() {
    _antecedents.dispose();
    _allergies.dispose();
    _traitements.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _payload => {
        'antecedents': _antecedents.text.trim(),
        'allergies': _allergies.text.trim(),
        'traitements_en_cours': _traitements.text.trim(),
        'ald': _ald,
      };

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
                final questionnaire = state.questionnaire;
                if (questionnaire != null) {
                  _antecedents.text =
                      questionnaire.payload['antecedents'] as String? ?? '';
                  _allergies.text =
                      questionnaire.payload['allergies'] as String? ?? '';
                  _traitements.text = questionnaire
                          .payload['traitements_en_cours'] as String? ??
                      '';
                }
                setState(() {
                  _ald = questionnaire?.payload['ald'] as bool? ?? false;
                  _readOnly =
                      questionnaire != null && questionnaire.status != 'draft';
                  _submittedAt = questionnaire?.submittedAt;
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
            },
            builder: (context, state) {
              if (_initialLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              final loading = state is MedicalQuestionnaireSaving;
              final fieldsEnabled = !loading && !_readOnly;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Avant votre rendez-vous',
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
                    NubiaTextField(
                      key: const Key('medical_questionnaire_antecedents'),
                      variant: NubiaTextFieldVariant.multiline,
                      controller: _antecedents,
                      label: 'Antécédents médicaux',
                      hint: 'Maladies, opérations, hospitalisations…',
                      enabled: fieldsEnabled,
                    ),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      key: const Key('medical_questionnaire_allergies'),
                      variant: NubiaTextFieldVariant.multiline,
                      controller: _allergies,
                      label: 'Allergies',
                      hint: 'Médicaments, latex, anesthésiques…',
                      enabled: fieldsEnabled,
                    ),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      key: const Key('medical_questionnaire_traitements'),
                      variant: NubiaTextFieldVariant.multiline,
                      controller: _traitements,
                      label: 'Traitements en cours',
                      hint: 'Médicaments pris actuellement…',
                      enabled: fieldsEnabled,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      key: const Key('medical_questionnaire_ald'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Affection de longue durée (ALD)'),
                      value: _ald,
                      onChanged: fieldsEnabled
                          ? (v) => setState(() => _ald = v)
                          : null,
                    ),
                    if (!_readOnly) ...[
                      const SizedBox(height: 24),
                      NubiaButton(
                        key: const Key('medical_questionnaire_submit_button'),
                        label: 'Envoyer au cabinet',
                        isLoading: loading,
                        onPressed: loading
                            ? null
                            : () => context
                                .read<MedicalQuestionnaireCubit>()
                                .submit(_payload),
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
                                .saveDraft(_payload),
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
}
