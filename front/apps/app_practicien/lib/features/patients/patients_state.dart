import 'dart:typed_data';

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

  /// Historique des RDV du patient dans le cabinet (#3372) — best-effort,
  /// vide si l'appel agenda échoue (la fiche reste utilisable).
  final List<CabinetAppointment> appointments;

  const PatientDetailLoaded(
    this.patient, {
    this.notesUpdating = false,
    this.notesError,
    this.appointments = const [],
  });

  PatientDetailLoaded copyWith({
    CabinetPatient? patient,
    bool? notesUpdating,
    String? notesError,
    bool clearNotesError = false,
    List<CabinetAppointment>? appointments,
  }) =>
      PatientDetailLoaded(
        patient ?? this.patient,
        notesUpdating: notesUpdating ?? this.notesUpdating,
        notesError: clearNotesError ? null : (notesError ?? this.notesError),
        appointments: appointments ?? this.appointments,
      );

  @override
  List<Object?> get props => [patient, notesUpdating, notesError, appointments];
}

class PatientDetailError extends PatientsState {
  final String message;
  const PatientDetailError(this.message);

  @override
  List<Object?> get props => [message];
}

class PatientPdfReady extends PatientsState {
  final Uint8List bytes;
  final String filename;
  const PatientPdfReady({required this.bytes, required this.filename});

  @override
  List<Object?> get props => [bytes, filename];
}

class PatientExportError extends PatientsState {
  final String message;
  const PatientExportError(this.message);

  @override
  List<Object?> get props => [message];
}
