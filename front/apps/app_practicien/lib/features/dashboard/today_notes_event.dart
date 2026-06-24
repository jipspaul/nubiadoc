import 'package:equatable/equatable.dart';

sealed class TodayNotesEvent extends Equatable {
  const TodayNotesEvent();

  @override
  List<Object?> get props => [];
}

final class TodayNotesLoadRequested extends TodayNotesEvent {
  const TodayNotesLoadRequested();
}
