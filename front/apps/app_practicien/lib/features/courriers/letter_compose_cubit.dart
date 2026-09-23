import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'letter_compose_state.dart';

/// Composition d'un courrier depuis la fiche patient (#7196) : choix du
/// modèle (#7197), champs libres pour les placeholders non résolus côté
/// serveur (ex. `correspondant.nom`, aucune entité correspondant côté
/// cabinet), génération PDF + ajout aux documents du patient. Importe aussi
/// un modèle `.docx` propre au cabinet (#7157/#7156).
class LetterComposeCubit extends Cubit<LetterComposeState> {
  LetterComposeCubit({
    required ListLetterTemplatesUseCase listTemplates,
    required GetCabinetPatientUseCase getPatient,
    required GenerateLetterUseCase generateLetter,
    required ImportLetterTemplateUseCase importTemplate,
  })  : _listTemplates = listTemplates,
        _getPatient = getPatient,
        _generateLetter = generateLetter,
        _importTemplate = importTemplate,
        super(const LetterComposeLoading());

  final ListLetterTemplatesUseCase _listTemplates;
  final GetCabinetPatientUseCase _getPatient;
  final GenerateLetterUseCase _generateLetter;
  final ImportLetterTemplateUseCase _importTemplate;

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

  /// Import d'un modèle `.docx` (#7157/#7156) — recharge la liste des
  /// modèles sur succès pour que le nouveau modèle apparaisse aussitôt dans
  /// [_TemplatePicker]. La réponse est renvoyée à l'appelant (dialog) pour
  /// son propre affichage d'erreur ; le rechargement est le seul effet
  /// observable côté état du cubit.
  Future<Either<Failure, LetterTemplateImportResult>> importTemplate({
    required String name,
    required String kind,
    required List<int> bytes,
    required String filename,
  }) async {
    final current = state;
    final result = await _importTemplate(
      name: name,
      kind: kind,
      bytes: bytes,
      filename: filename,
    );
    if (current is LetterComposeReady) {
      await result.fold(
        (_) async {},
        (_) async {
          final refreshed = await _listTemplates();
          refreshed.fold(
            (_) {},
            (templates) => emit(LetterComposeReady(
              templates: templates,
              patient: current.patient,
            )),
          );
        },
      );
    }
    return result;
  }
}
