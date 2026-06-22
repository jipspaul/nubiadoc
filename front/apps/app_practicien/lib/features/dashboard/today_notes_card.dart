import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// ---------------------------------------------------------------------------
// Entity
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
        status: 'completed',
      ),
      ClinicalNoteSummary(
        timestamp: now.subtract(const Duration(hours: 1)),
        patientInitials: 'JD',
        status: 'in_progress',
      ),
      ClinicalNoteSummary(
        timestamp: now.subtract(const Duration(hours: 2)),
        patientInitials: 'AB',
        status: 'completed',
      ),
    ]));
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class TodayNotesCard extends StatelessWidget {
  const TodayNotesCard({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => TodayNotesBloc()..add(const TodayNotesLoadRequested()),
      child: const TodayNotesCardBody(),
    );
  }
}

class TodayNotesCardBody extends StatelessWidget {
  const TodayNotesCardBody({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TodayNotesBloc, TodayNotesState>(
      builder: (context, state) {
        return Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  'Notes du jour',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              switch (state) {
                TodayNotesLoaded(:final notes) when notes.isEmpty =>
                  const Padding(
                    key: Key('today_notes_empty'),
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text('Aucune consultation aujourd\'hui'),
                  ),
                TodayNotesLoaded(:final notes) => Column(
                    key: const Key('today_notes_list'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < notes.length.clamp(0, 3); i++)
                        _NoteTile(note: notes[i]),
                    ],
                  ),
                _ => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              },
            ],
          ),
        );
      },
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note});
  final ClinicalNoteSummary note;

  String _timeLabel(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        child: Text(note.patientInitials),
      ),
      title: Text(note.patientInitials),
      subtitle: Text(_timeLabel(note.timestamp)),
      trailing: Chip(
        label: Text(note.status),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
