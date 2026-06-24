import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'today_notes_event.dart';
import 'today_notes_state.dart';

class TodayNotesBloc extends Bloc<TodayNotesEvent, TodayNotesState> {
  final GetTodayNotesUseCase _getTodayNotes;

  TodayNotesBloc({required GetTodayNotesUseCase getTodayNotes})
      : _getTodayNotes = getTodayNotes,
        super(const TodayNotesInitial()) {
    on<TodayNotesLoadRequested>(_onLoad);
  }

  Future<void> _onLoad(
    TodayNotesLoadRequested event,
    Emitter<TodayNotesState> emit,
  ) async {
    emit(const TodayNotesLoading());
    try {
      final result = await _getTodayNotes();
      result.fold(
        (failure) => emit(TodayNotesError(failure.message)),
        (notes) =>
            notes.isEmpty ? emit(const TodayNotesEmpty()) : emit(TodayNotesLoaded(notes)),
      );
    } catch (_) {
      emit(const TodayNotesError('Erreur de chargement.'));
    }
  }
}
