import 'package:nubia_domain/nubia_domain.dart';

abstract class PatientsState {
  const PatientsState();
}

class PatientsInitial extends PatientsState {
  const PatientsInitial();

  @override
  bool operator ==(Object other) => other is PatientsInitial;

  @override
  int get hashCode => runtimeType.hashCode;
}

class PatientsLoading extends PatientsState {
  const PatientsLoading();

  @override
  bool operator ==(Object other) => other is PatientsLoading;

  @override
  int get hashCode => runtimeType.hashCode;
}

class PatientsLoaded extends PatientsState {
  const PatientsLoaded(this.patients);

  final List<CabinetPatient> patients;

  @override
  bool operator ==(Object other) =>
      other is PatientsLoaded &&
      other.patients.length == patients.length &&
      List.generate(patients.length, (i) => other.patients[i] == patients[i])
          .every((b) => b);

  @override
  int get hashCode => Object.hashAll(patients);
}

class PatientsError extends PatientsState {
  const PatientsError(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is PatientsError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

/// Soumission du formulaire de création en cours (#4038).
class PatientsCreating extends PatientsState {
  const PatientsCreating();

  @override
  bool operator ==(Object other) => other is PatientsCreating;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Création réussie — le patient créé est renvoyé pour navigation/feedback.
class PatientsCreateSuccess extends PatientsState {
  const PatientsCreateSuccess(this.patient);

  final CabinetPatient patient;

  @override
  bool operator ==(Object other) =>
      other is PatientsCreateSuccess && other.patient == patient;

  @override
  int get hashCode => patient.hashCode;
}

class PatientsCreateError extends PatientsState {
  const PatientsCreateError(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is PatientsCreateError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}
