import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'letter_compose_state.dart';

/// Composition d'un courrier depuis la fiche patient (#7196) : choix du
/// modèle (#7197), champs libres pour les placeholders non résolus côté
/// serveur (ex. `correspondant.nom`, aucune entité correspondant côté
/// cabinet), génération PDF + ajout aux documents du patient.
class LetterComposeCubit extends Cubit<LetterComposeState> {
  LetterComposeCubit({
    required ListLetterTemplatesUseCase listTemplates,
    required GetCabinetPatientUseCase getPatient,
    required GenerateLetterUseCase generateLetter,
  })  : _listTemplates = listTemplates,
        _getPatient = getPatient,
        _generateLetter = generateLetter,
        super(const LetterComposeLoading());

  final ListLetterTemplatesUseCase _listTemplates;
  final GetCabinetPatientUseCase _getPatient;
  final GenerateLetterUseCase _generateLetter;

  Future<void> load(String patientId) async {
    emit(const LetterComposeLoading());
    final templatesResult = await _listTemplates();
    final failure = templatesResult.fold((f) => f, (_) => null);
    if (failure != null) {
      emit(LetterComposeError(failure.message));
      return;
    }
    final templates = templatesResult.fold((_) => <LetterTemplate>[], (v) => v);
    final patient = (await _getPatient(patientId)).fold((_) => null, (v) => v);
    emit(LetterComposeReady(templates: templates, patient: patient));
  }

  Future<void> generate(
    String patientId, {
    required String templateId,
    required Map<String, String> overrides,
  }) async {
    final current = state;
    if (current is! LetterComposeReady || current.submitting) return;

    emit(LetterComposeReady(
      templates: current.templates,
      patient: current.patient,
      submitting: true,
    ));
    final result = await _generateLetter(
      patientId,
      templateId: templateId,
      overrides: overrides,
    );
    result.fold(
      (failure) => emit(LetterComposeReady(
        templates: current.templates,
        patient: current.patient,
        error: failure.message,
      )),
      (letter) => emit(LetterComposeGenerated(letter)),
    );
  }
}
