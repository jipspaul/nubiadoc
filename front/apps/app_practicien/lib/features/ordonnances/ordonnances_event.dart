import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

abstract class OrdonnancesEvent extends Equatable {
  const OrdonnancesEvent();

  @override
  List<Object?> get props => [];
}

class OrdonnancesCreateRequested extends OrdonnancesEvent {
  final String patientId;
  final List<PrescriptionItem> items;

  const OrdonnancesCreateRequested({
    required this.patientId,
    required this.items,
  });

  @override
  List<Object?> get props => [patientId, items];
}

class OrdonnancesSignRequested extends OrdonnancesEvent {
  final String prescriptionId;

  const OrdonnancesSignRequested(this.prescriptionId);

  @override
  List<Object?> get props => [prescriptionId];
}
