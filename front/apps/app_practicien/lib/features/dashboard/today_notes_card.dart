import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// ─── Entity ─────────────────────────────────────────────────────────────────

class ClinicalNoteSummary extends Equatable {
  const ClinicalNoteSummary({
    required this.timestamp,
    required this.patientInitials,
    required this.status,
  });

  final DateTime timestamp;
  final String patientInitials;
  final String status;

  @override
  List<Object?> get props => [timestamp, patientInitials, status];
}

// ─── Events ─────────────────────────────────────────────────────────────────

sealed class TodayNotesEvent extends Equatable {
  const TodayNotesEvent();

  @override
  List<Object?> get props => [];
}

final class TodayNotesLoadRequested extends TodayNotesEvent {
  const TodayNotesLoadRequested();
}

// ─── States ─────────────────────────────────────────────────────────────────

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
  const TodayNotesLoaded(this.notes);

  final List<ClinicalNoteSummary> notes;

  @override
  List<Object?> get props => [notes];
}

final class TodayNotesError extends TodayNotesState {
  const TodayNotesError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

// ─── BLoC ───────────────────────────────────────────────────────────────────

class TodayNotesBloc extends Bloc<TodayNotesEvent, TodayNotesState> {
  TodayNotesBloc() : super(const TodayNotesInitial()) {
    on<TodayNotesLoadRequested>(_onLoad);
  }

  Future<void> _onLoad(
    TodayNotesLoadRequested event,
    Emitter<TodayNotesState> emit,
  ) async {
    emit(const TodayNotesLoading());
    emit(TodayNotesLoaded([
      ClinicalNoteSummary(
        timestamp: DateTime(2026, 6, 22, 9, 0),
        patientInitials: 'JD',
        status: 'terminée',
      ),
      ClinicalNoteSummary(
        timestamp: DateTime(2026, 6, 22, 10, 30),
        patientInitials: 'ML',
        status: 'terminée',
      ),
      ClinicalNoteSummary(
        timestamp: DateTime(2026, 6, 22, 11, 0),
        patientInitials: 'AB',
        status: 'en cours',
      ),
    ]));
  }
}

// ─── Widget ─────────────────────────────────────────────────────────────────

String _formatTime(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

class TodayNotesCard extends StatelessWidget {
  const TodayNotesCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Notes du jour',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            BlocBuilder<TodayNotesBloc, TodayNotesState>(
              builder: (context, state) {
                if (state is! TodayNotesLoaded) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                if (state.notes.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Aucune consultation aujourd\'hui',
                      key: Key('today_notes_empty'),
                    ),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final note in state.notes.take(3))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Text(
                          _formatTime(note.timestamp),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        title: Text(note.patientInitials),
                        subtitle: Text(note.status),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
