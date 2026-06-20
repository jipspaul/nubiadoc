import 'package:equatable/equatable.dart';

abstract class PatientsEvent extends Equatable {
  const PatientsEvent();

  @override
  List<Object?> get props => [];
}

class PatientsLoadRequested extends PatientsEvent {
  const PatientsLoadRequested();
}

class PatientsDetailLoadRequested extends PatientsEvent {
  final String id;
  const PatientsDetailLoadRequested(this.id);

  @override
  List<Object?> get props => [id];
}

class PatientsNotesUpdateRequested extends PatientsEvent {
  final String id;
  final String notes;
  const PatientsNotesUpdateRequested(this.id, this.notes);

  @override
  List<Object?> get props => [id, notes];
}
