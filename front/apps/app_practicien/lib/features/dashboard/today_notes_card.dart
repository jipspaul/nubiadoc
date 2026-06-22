import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class ClinicalNoteSummary extends Equatable {
  final String id;
  final DateTime timestamp;
  final String patientInitials;
  final String status;

  const ClinicalNoteSummary({
    required this.id,
    required this.timestamp,
    required this.patientInitials,
    required this.status,
  });

  @override
  List<Object?> get props => [id, timestamp, patientInitials, status];
}

// ---------------------------------------------------------------------------
// Use case interface
// ---------------------------------------------------------------------------

abstract class GetTodayNotesUseCase {
  Future<List<ClinicalNoteSummary>> call();
}

class StubGetTodayNotesUseCase implements GetTodayNotesUseCase {
  const StubGetTodayNotesUseCase();

  @override
  Future<List<ClinicalNoteSummary>> call() async => [
        ClinicalNoteSummary(
          id: 'n1',
          timestamp: DateTime(2026, 6, 22, 9, 15),
          patientInitials: 'JD',
          status: 'completed',
        ),
        ClinicalNoteSummary(
          id: 'n2',
          timestamp: DateTime(2026, 6, 22, 10, 30),
          patientInitials: 'AM',
          status: 'in_progress',
        ),
        ClinicalNoteSummary(
          id: 'n3',
          timestamp: DateTime(2026, 6, 22, 11, 45),
          patientInitials: 'CB',
          status: 'completed',
        ),
      ];
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
  final List<ClinicalNoteSummary> notes;

  const TodayNotesLoaded(this.notes);

  @override
  List<Object?> get props => [notes];
}

// ---------------------------------------------------------------------------
// Bloc
// ---------------------------------------------------------------------------

class TodayNotesBloc extends Bloc<TodayNotesEvent, TodayNotesState> {
  final GetTodayNotesUseCase _getTodayNotes;

  TodayNotesBloc({GetTodayNotesUseCase? getTodayNotes})
      : _getTodayNotes = getTodayNotes ?? const StubGetTodayNotesUseCase(),
        super(const TodayNotesInitial()) {
    on<TodayNotesLoadRequested>(_onLoad);
  }

  Future<void> _onLoad(
    TodayNotesLoadRequested event,
    Emitter<TodayNotesState> emit,
  ) async {
    emit(const TodayNotesLoading());
    final notes = await _getTodayNotes();
    emit(TodayNotesLoaded(notes.take(3).toList()));
  }
}

// ---------------------------------------------------------------------------
// Widget — reads TodayNotesBloc from context
// ---------------------------------------------------------------------------

class TodayNotesCard extends StatelessWidget {
  const TodayNotesCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Notes du jour',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          BlocBuilder<TodayNotesBloc, TodayNotesState>(
            builder: (context, state) => switch (state) {
              TodayNotesInitial() || TodayNotesLoading() => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              TodayNotesLoaded(:final notes) => notes.isEmpty
                  ? const Padding(
                      key: Key('today_notes_empty'),
                      padding: EdgeInsets.all(16),
                      child: Text('Aucune consultation aujourd\'hui'),
                    )
                  : Column(
                      children: [
                        for (final note in notes)
                          ListTile(
                            key: Key('today_note_${note.id}'),
                            leading: CircleAvatar(
                              child: Text(note.patientInitials),
                            ),
                            title: Text(note.patientInitials),
                            subtitle: Text(note.status),
                            trailing: Text(_fmt(note.timestamp)),
                          ),
                      ],
                    ),
            },
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
