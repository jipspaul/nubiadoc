import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class ClinicalNoteSummary extends Equatable {
  final DateTime timestamp;
  final String patientInitials;
  final String status;

  const ClinicalNoteSummary({
    required this.timestamp,
    required this.patientInitials,
    required this.status,
  });

  @override
  List<Object?> get props => [timestamp, patientInitials, status];
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
    final now = DateTime.now();
    emit(TodayNotesLoaded([
      ClinicalNoteSummary(
        timestamp: now.subtract(const Duration(minutes: 15)),
        patientInitials: 'MD',
        status: 'terminée',
      ),
      ClinicalNoteSummary(
        timestamp: now.subtract(const Duration(minutes: 45)),
        patientInitials: 'JP',
        status: 'en cours',
      ),
      ClinicalNoteSummary(
        timestamp: now.subtract(const Duration(hours: 1, minutes: 20)),
        patientInitials: 'AL',
        status: 'terminée',
      ),
    ]));
  }
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class TodayNotesCard extends StatelessWidget {
  const TodayNotesCard({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TodayNotesBloc, TodayNotesState>(
      builder: (context, state) {
        final notes = state is TodayNotesLoaded
            ? state.notes.take(3).toList()
            : <ClinicalNoteSummary>[];
        return _NotesCardView(notes: notes);
      },
    );
  }
}

class _NotesCardView extends StatelessWidget {
  const _NotesCardView({required this.notes});

  final List<ClinicalNoteSummary> notes;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('today_notes_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Notes du jour',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          if (notes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Aucune consultation aujourd\'hui',
                key: Key('today_notes_empty'),
              ),
            )
          else
            for (var i = 0; i < notes.length; i++)
              ListTile(
                key: Key('today_note_$i'),
                leading: CircleAvatar(
                  child: Text(notes[i].patientInitials),
                ),
                title: Text(_formatTime(notes[i].timestamp)),
                trailing: Chip(
                  label: Text(notes[i].status),
                  visualDensity: VisualDensity.compact,
                ),
              ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
