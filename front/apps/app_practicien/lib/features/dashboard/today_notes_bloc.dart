import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

sealed class TodayNotesEvent extends Equatable {
  const TodayNotesEvent();

  @override
  List<Object?> get props => [];
}

final class TodayNotesLoadRequested extends TodayNotesEvent {
  const TodayNotesLoadRequested();
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

sealed class TodayNotesState extends Equatable {
  const TodayNotesState();

  @override
  List<Object?> get props => [];
}

final class TodayNotesInitial extends TodayNotesState {
  const TodayNotesInitial();
}

final class TodayNotesLoading extends TodayNotesState {
  const TodayNotesLoading();
}

final class TodayNotesLoaded extends TodayNotesState {
  final List<ClinicalNoteSummary> entries;

  const TodayNotesLoaded(this.entries);

  @override
  List<Object?> get props => [entries];
}

final class TodayNotesError extends TodayNotesState {
  final String message;

  const TodayNotesError(this.message);

  @override
  List<Object?> get props => [message];
}

// ---------------------------------------------------------------------------
// BLoC
// ---------------------------------------------------------------------------

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
        (entries) => emit(TodayNotesLoaded(entries)),
      );
    } catch (_) {
      emit(const TodayNotesError('Erreur de chargement.'));
    }
  }
}
