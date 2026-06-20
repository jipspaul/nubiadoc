import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

abstract class PatientsState extends Equatable {
  const PatientsState();

  @override
  List<Object?> get props => [];
}

class PatientsInitial extends PatientsState {
  const PatientsInitial();
}

class PatientsLoading extends PatientsState {
  const PatientsLoading();
}

class PatientsLoaded extends PatientsState {
  final List<CabinetPatient> patients;
  const PatientsLoaded(this.patients);

  @override
  List<Object?> get props => [patients];
}

class PatientsError extends PatientsState {
  final String message;
  const PatientsError(this.message);

  @override
  List<Object?> get props => [message];
}

class PatientDetailLoaded extends PatientsState {
  final CabinetPatient patient;
  final bool notesUpdating;
  final String? notesError;

  const PatientDetailLoaded(
    this.patient, {
    this.notesUpdating = false,
    this.notesError,
  });

  PatientDetailLoaded copyWith({
    CabinetPatient? patient,
    bool? notesUpdating,
    String? notesError,
    bool clearNotesError = false,
  }) =>
      PatientDetailLoaded(
        patient ?? this.patient,
        notesUpdating: notesUpdating ?? this.notesUpdating,
        notesError: clearNotesError ? null : (notesError ?? this.notesError),
      );

  @override
  List<Object?> get props => [patient, notesUpdating, notesError];
}

class PatientDetailError extends PatientsState {
  final String message;
  const PatientDetailError(this.message);

  @override
  List<Object?> get props => [message];
}
