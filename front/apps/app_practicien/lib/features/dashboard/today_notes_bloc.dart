import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class TodayNoteEntry extends Equatable {
  final String id;
  final DateTime timestamp;
  final String patientInitials;
  final String status;

  const TodayNoteEntry({
    required this.id,
    required this.timestamp,
    required this.patientInitials,
    required this.status,
  });

  @override
  List<Object?> get props => [id, timestamp, patientInitials, status];
}

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
  final List<TodayNoteEntry> entries;

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
  TodayNotesBloc() : super(const TodayNotesInitial()) {
    on<TodayNotesLoadRequested>(_onLoad);
  }

  Future<void> _onLoad(
    TodayNotesLoadRequested event,
    Emitter<TodayNotesState> emit,
  ) async {
    emit(const TodayNotesLoading());
    // Stub — la route API /v1/cabinet/today-notes viendra plus tard.
    final entries = [
      TodayNoteEntry(
        id: 'note-1',
        timestamp: DateTime(2026, 6, 22, 9, 0),
        patientInitials: 'MD',
        status: 'Terminée',
      ),
      TodayNoteEntry(
        id: 'note-2',
        timestamp: DateTime(2026, 6, 22, 10, 30),
        patientInitials: 'JD',
        status: 'En cours',
      ),
      TodayNoteEntry(
        id: 'note-3',
        timestamp: DateTime(2026, 6, 22, 11, 0),
        patientInitials: 'CB',
        status: 'Terminée',
      ),
    ];
    emit(TodayNotesLoaded(entries));
  }
}
