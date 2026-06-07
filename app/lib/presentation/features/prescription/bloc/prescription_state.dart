import 'package:equatable/equatable.dart';
import 'package:nubia_patient/domain/entities/prescription.dart';

sealed class PrescriptionState extends Equatable {
  const PrescriptionState();

  @override
  List<Object?> get props => [];
}

/// État initial : formulaire vide, aucun patient sélectionné.
final class PrescriptionInitial extends PrescriptionState {
  final String? patientId;
  final String? patientName;
  final List<PrescriptionItem> items;

  const PrescriptionInitial({
    this.patientId,
    this.patientName,
    this.items = const [],
  });

  PrescriptionInitial copyWith({
    String? patientId,
    String? patientName,
    List<PrescriptionItem>? items,
  }) =>
      PrescriptionInitial(
        patientId: patientId ?? this.patientId,
        patientName: patientName ?? this.patientName,
        items: items ?? this.items,
      );

  @override
  List<Object?> get props => [patientId, patientName, items];
}

/// Création ou signature en cours.
final class PrescriptionLoading extends PrescriptionState {
  final Prescription? current;

  const PrescriptionLoading({this.current});

  @override
  List<Object?> get props => [current];
}

/// Ordonnance créée (draft) ou signée.
final class PrescriptionLoaded extends PrescriptionState {
  final Prescription prescription;

  const PrescriptionLoaded(this.prescription);

  @override
  List<Object?> get props => [prescription];
}

/// Erreur réseau ou validation.
final class PrescriptionError extends PrescriptionState {
  final String message;
  /// Ordonnance courante (si l'erreur survient pendant la signature).
  final Prescription? current;

  const PrescriptionError(this.message, {this.current});

  @override
  List<Object?> get props => [message, current];
}
