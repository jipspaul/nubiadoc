import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'questionnaire_templates_event.dart';
import 'questionnaire_templates_state.dart';

/// Écran « Modèle de questionnaire médical » (#7158) : catalogue global en
/// lecture, modèle propre au cabinet créé/édité ici — au plus un à la fois.
class QuestionnaireTemplatesBloc
    extends Bloc<QuestionnaireTemplatesEvent, QuestionnaireTemplatesState>
    with SafeEmitMixin<QuestionnaireTemplatesState> {
  QuestionnaireTemplatesBloc({
    required ListQuestionnaireTemplatesUseCase listTemplates,
    required CreateQuestionnaireTemplateUseCase createTemplate,
    required PatchQuestionnaireTemplateUseCase patchTemplate,
  })  : _listTemplates = listTemplates,
        _createTemplate = createTemplate,
        _patchTemplate = patchTemplate,
        super(const QuestionnaireTemplatesInitial()) {
    on<QuestionnaireTemplatesLoadRequested>(_onLoad);
    on<QuestionnaireTemplatesCreateRequested>(_onCreate);
    on<QuestionnaireTemplatesUpdateRequested>(_onUpdate);
  }

  final ListQuestionnaireTemplatesUseCase _listTemplates;
  final CreateQuestionnaireTemplateUseCase _createTemplate;
  final PatchQuestionnaireTemplateUseCase _patchTemplate;

  Future<void> _onLoad(
    QuestionnaireTemplatesLoadRequested event,
    Emitter<QuestionnaireTemplatesState> emit,
  ) async {
    emit(const QuestionnaireTemplatesLoading());
    final result = await _listTemplates();
    result.fold(
      (failure) => safeEmit(QuestionnaireTemplatesError(failure.message)),
      (templates) =>
          safeEmit(QuestionnaireTemplatesLoaded(templates: templates)),
    );
  }

  Future<void> _onCreate(
    QuestionnaireTemplatesCreateRequested event,
    Emitter<QuestionnaireTemplatesState> emit,
  ) async {
    final current = state;
    if (current is! QuestionnaireTemplatesLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result = await _createTemplate(
      title: event.title,
      schema: event.schema,
    );
    result.fold(
      (failure) => safeEmit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (_) => add(const QuestionnaireTemplatesLoadRequested()),
    );
  }

  Future<void> _onUpdate(
    QuestionnaireTemplatesUpdateRequested event,
    Emitter<QuestionnaireTemplatesState> emit,
  ) async {
    final current = state;
    if (current is! QuestionnaireTemplatesLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result = await _patchTemplate(
      event.id,
      title: event.title,
      schema: event.schema,
    );
    result.fold(
      (failure) => safeEmit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (_) => add(const QuestionnaireTemplatesLoadRequested()),
    );
  }
}
