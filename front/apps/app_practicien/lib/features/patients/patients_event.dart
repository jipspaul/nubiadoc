import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

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

class PatientExportPdfRequested extends PatientsEvent {
  final CabinetPatient patient;
  const PatientExportPdfRequested(this.patient);

  @override
  List<Object?> get props => [patient];
}
