import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'consent_templates_event.dart';
import 'consent_templates_state.dart';

/// Écran « Modèles de consentement » (#7198, DP-F6.c) : catalogue global en
/// lecture, modèles du cabinet créés/édités ici.
class ConsentTemplatesBloc
    extends Bloc<ConsentTemplatesEvent, ConsentTemplatesState>
    with SafeEmitMixin<ConsentTemplatesState> {
  ConsentTemplatesBloc({
    required ListConsentTemplatesUseCase listTemplates,
    required CreateConsentTemplateUseCase createTemplate,
    required PatchConsentTemplateUseCase patchTemplate,
  })  : _listTemplates = listTemplates,
        _createTemplate = createTemplate,
        _patchTemplate = patchTemplate,
        super(const ConsentTemplatesInitial()) {
    on<ConsentTemplatesLoadRequested>(_onLoad);
    on<ConsentTemplatesCreateRequested>(_onCreate);
    on<ConsentTemplatesUpdateRequested>(_onUpdate);
  }

  final ListConsentTemplatesUseCase _listTemplates;
  final CreateConsentTemplateUseCase _createTemplate;
  final PatchConsentTemplateUseCase _patchTemplate;

  Future<void> _onLoad(
    ConsentTemplatesLoadRequested event,
    Emitter<ConsentTemplatesState> emit,
  ) async {
    emit(const ConsentTemplatesLoading());
    final result = await _listTemplates();
    result.fold(
      (failure) => safeEmit(ConsentTemplatesError(failure.message)),
      (templates) => safeEmit(ConsentTemplatesLoaded(templates: templates)),
    );
  }

  Future<void> _onCreate(
    ConsentTemplatesCreateRequested event,
    Emitter<ConsentTemplatesState> emit,
  ) async {
    final current = state;
    if (current is! ConsentTemplatesLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result = await _createTemplate(
      actCategory: event.actCategory,
      title: event.title,
      bodyMarkdown: event.bodyMarkdown,
    );
    result.fold(
      (failure) => safeEmit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (_) => add(const ConsentTemplatesLoadRequested()),
    );
  }

  Future<void> _onUpdate(
    ConsentTemplatesUpdateRequested event,
    Emitter<ConsentTemplatesState> emit,
  ) async {
    final current = state;
    if (current is! ConsentTemplatesLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result = await _patchTemplate(
      event.id,
      actCategory: event.actCategory,
      title: event.title,
      bodyMarkdown: event.bodyMarkdown,
    );
    result.fold(
      (failure) => safeEmit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (_) => add(const ConsentTemplatesLoadRequested()),
    );
  }
}
