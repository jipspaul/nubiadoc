//! Écran de saisie du questionnaire médical patient (#4109) — antécédents,
//! allergies, traitements en cours, ALD. Proposé avant le prochain RDV
//! (accessible depuis `mes_rdv_page.dart`, qui fournit le `cabinetId`).

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
              final loading = state is MedicalQuestionnaireSaving;
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
                      enabled: !loading,
                    ),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      key: const Key('medical_questionnaire_allergies'),
                      variant: NubiaTextFieldVariant.multiline,
                      controller: _allergies,
                      label: 'Allergies',
                      hint: 'Médicaments, latex, anesthésiques…',
                      enabled: !loading,
                    ),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      key: const Key('medical_questionnaire_traitements'),
                      variant: NubiaTextFieldVariant.multiline,
                      controller: _traitements,
                      label: 'Traitements en cours',
                      hint: 'Médicaments pris actuellement…',
                      enabled: !loading,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      key: const Key('medical_questionnaire_ald'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Affection de longue durée (ALD)'),
                      value: _ald,
                      onChanged:
                          loading ? null : (v) => setState(() => _ald = v),
                    ),
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
                      key: const Key('medical_questionnaire_save_draft_button'),
                      label: 'Enregistrer le brouillon',
                      variant: NubiaButtonVariant.secondary,
                      onPressed: loading
                          ? null
                          : () => context
                              .read<MedicalQuestionnaireCubit>()
                              .saveDraft(_payload),
                    ),
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
