import 'package:equatable/equatable.dart';

import '../models/prescription.dart';

sealed class PrescriptionState extends Equatable {
  const PrescriptionState();

  @override
  List<Object?> get props => [];
}

final class PrescriptionInitial extends PrescriptionState {
  const PrescriptionInitial();
}

final class PrescriptionLoading extends PrescriptionState {
  const PrescriptionLoading();
}

final class PrescriptionListLoaded extends PrescriptionState {
  const PrescriptionListLoaded({
    required this.prescriptions,
    required this.patients,
  });

  final List<Prescription> prescriptions;
  final List<PatientSummary> patients;

  @override
  List<Object?> get props => [prescriptions, patients];
}

/// Ordonnance créée avec succès — récap affiché.
final class PrescriptionCreated extends PrescriptionState {
  const PrescriptionCreated({
    required this.prescription,
    required this.patients,
  });

  final Prescription prescription;
  final List<PatientSummary> patients;

  @override
  List<Object?> get props => [prescription, patients];
}

/// Ordonnance signée avec succès.
final class PrescriptionSigned extends PrescriptionState {
  const PrescriptionSigned({
    required this.prescription,
    required this.patients,
  });

  final Prescription prescription;
  final List<PatientSummary> patients;

  @override
  List<Object?> get props => [prescription, patients];
}

final class PrescriptionError extends PrescriptionState {
  const PrescriptionError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
