import 'package:equatable/equatable.dart';

import '../models/prescription.dart';

sealed class PrescriptionEvent extends Equatable {
  const PrescriptionEvent();

  @override
  List<Object?> get props => [];
}

/// Charge la liste des ordonnances et la liste des patients.
final class PrescriptionLoadRequested extends PrescriptionEvent {
  const PrescriptionLoadRequested();
}

/// Crée une ordonnance (POST /v1/cabinet/prescriptions).
final class PrescriptionCreateRequested extends PrescriptionEvent {
  const PrescriptionCreateRequested({
    required this.patientId,
    required this.items,
  });

  final String patientId;
  final List<PrescriptionItem> items;

  @override
  List<Object?> get props => [patientId, items];
}

/// Signe une ordonnance (POST /v1/cabinet/prescriptions/{id}/sign).
final class PrescriptionSignRequested extends PrescriptionEvent {
  const PrescriptionSignRequested({required this.id});

  final String id;

  @override
  List<Object?> get props => [id];
}
