import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class MedicalQuestionnaireState extends Equatable {
  const MedicalQuestionnaireState();

  @override
  List<Object?> get props => [];
}

final class MedicalQuestionnaireIdle extends MedicalQuestionnaireState {
  const MedicalQuestionnaireIdle();
}

/// Chargement initial terminé — [questionnaire] est `null` si le patient n'a
/// encore rien soumis pour ce cabinet.
final class MedicalQuestionnaireLoaded extends MedicalQuestionnaireState {
  final MedicalQuestionnaire? questionnaire;
  const MedicalQuestionnaireLoaded(this.questionnaire);

  @override
  List<Object?> get props => [questionnaire];
}

final class MedicalQuestionnaireSaving extends MedicalQuestionnaireState {
  const MedicalQuestionnaireSaving();
}

/// Brouillon enregistré — reste sur l'écran (pas de navigation, le patient
/// peut continuer à compléter le questionnaire).
final class MedicalQuestionnaireSaved extends MedicalQuestionnaireState {
  const MedicalQuestionnaireSaved();
}

/// Soumis au cabinet — terminal, la page navigue ailleurs.
final class MedicalQuestionnaireSubmitted extends MedicalQuestionnaireState {
  const MedicalQuestionnaireSubmitted();
}

final class MedicalQuestionnaireError extends MedicalQuestionnaireState {
  final String message;
  const MedicalQuestionnaireError(this.message);

  @override
  List<Object?> get props => [message];
}

/// Cubit du questionnaire médical patient (#4109).
///
/// Quoi : précharge le questionnaire existant (`GET`, #4459) puis enregistre
/// un brouillon (`saveDraft`) et/ou le soumet au cabinet (`submit`) pour le
/// [cabinetId] du prochain RDV.
///
/// `saveDraft`/`submit` gèrent eux-mêmes la création vs. mise à jour du
/// brouillon existant (409 sur `POST` → bascule sur `PATCH`, 404 sur `PATCH`
/// → bascule sur `POST`) plutôt que d'exiger que l'appelant sache si un
/// brouillon existe déjà.
///
/// Modes d'échec : toute erreur non 409/404 → `MedicalQuestionnaireError`
/// (le formulaire reste rempli, aucune perte de saisie).
class MedicalQuestionnaireCubit extends Cubit<MedicalQuestionnaireState>
    with SafeEmitMixin<MedicalQuestionnaireState> {
  MedicalQuestionnaireCubit({
    required this.cabinetId,
    required CreateMedicalQuestionnaireUseCase create,
    required PatchMedicalQuestionnaireUseCase patch,
    required GetMedicalQuestionnaireUseCase get,
  })  : _create = create,
        _patch = patch,
        _get = get,
        super(const MedicalQuestionnaireIdle()) {
    _load();
  }

  final String cabinetId;
  final CreateMedicalQuestionnaireUseCase _create;
  final PatchMedicalQuestionnaireUseCase _patch;
  final GetMedicalQuestionnaireUseCase _get;

  Future<void> _load() async {
    final result = await _get(cabinetId: cabinetId);
    result.fold(
      (_) => safeEmit(const MedicalQuestionnaireLoaded(null)),
      (questionnaire) => safeEmit(MedicalQuestionnaireLoaded(questionnaire)),
    );
  }

  Future<void> saveDraft(Map<String, dynamic> payload) async {
    emit(const MedicalQuestionnaireSaving());
    final result = await _create(cabinetId: cabinetId, payload: payload);
    result.fold(
      (failure) async {
        if (_isConflict(failure)) {
          final patched = await _patch(cabinetId: cabinetId, payload: payload);
          patched.fold(
            (f) => safeEmit(MedicalQuestionnaireError(f.message)),
            (_) => safeEmit(const MedicalQuestionnaireSaved()),
          );
          return;
        }
        safeEmit(MedicalQuestionnaireError(failure.message));
      },
      (_) => safeEmit(const MedicalQuestionnaireSaved()),
    );
  }

  Future<void> submit(Map<String, dynamic> payload) async {
    emit(const MedicalQuestionnaireSaving());
    final result = await _patch(
      cabinetId: cabinetId,
      payload: payload,
      submit: true,
    );
    result.fold(
      (failure) async {
        if (failure is NotFoundFailure) {
          final created = await _create(cabinetId: cabinetId, payload: payload);
          final createFailure = created.fold((f) => f, (_) => null);
          if (createFailure != null) {
            safeEmit(MedicalQuestionnaireError(createFailure.message));
            return;
          }
          final submitted = await _patch(cabinetId: cabinetId, submit: true);
          submitted.fold(
            (f) => safeEmit(MedicalQuestionnaireError(f.message)),
            (_) => safeEmit(const MedicalQuestionnaireSubmitted()),
          );
          return;
        }
        safeEmit(MedicalQuestionnaireError(failure.message));
      },
      (_) => safeEmit(const MedicalQuestionnaireSubmitted()),
    );
  }

  bool _isConflict(Failure failure) =>
      failure is ServerFailure && failure.statusCode == 409;
}
