import 'package:equatable/equatable.dart';
import 'package:nubia_patient/domain/entities/prescription.dart';

sealed class PrescriptionEvent extends Equatable {
  const PrescriptionEvent();

  @override
  List<Object?> get props => [];
}

/// Ajoute une ligne médicament au brouillon local (pas encore envoyée à l'API).
final class PrescriptionItemAdded extends PrescriptionEvent {
  final PrescriptionItem item;

  const PrescriptionItemAdded(this.item);

  @override
  List<Object?> get props => [item];
}

/// Supprime une ligne médicament du brouillon local par index.
final class PrescriptionItemRemoved extends PrescriptionEvent {
  final int index;

  const PrescriptionItemRemoved(this.index);

  @override
  List<Object?> get props => [index];
}

/// Sélectionne ou modifie le patient cible.
final class PrescriptionPatientSelected extends PrescriptionEvent {
  final String patientId;
  final String patientName;

  const PrescriptionPatientSelected({
    required this.patientId,
    required this.patientName,
  });

  @override
  List<Object?> get props => [patientId, patientName];
}

/// Lance la création de l'ordonnance via POST /v1/cabinet/prescriptions.
final class PrescriptionCreateRequested extends PrescriptionEvent {
  const PrescriptionCreateRequested();
}

/// Lance la signature via POST /v1/cabinet/prescriptions/{id}/sign.
final class PrescriptionSignRequested extends PrescriptionEvent {
  const PrescriptionSignRequested();
}
