import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

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

final class TodayNotesEmpty extends TodayNotesState {
  const TodayNotesEmpty();
}

final class TodayNotesError extends TodayNotesState {
  final String message;

  const TodayNotesError(this.message);

  @override
  List<Object?> get props => [message];
}
