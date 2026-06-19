import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

abstract class OrdonnancesState extends Equatable {
  const OrdonnancesState();

  @override
  List<Object?> get props => [];
}

class OrdonnancesInitial extends OrdonnancesState {
  const OrdonnancesInitial();
}

class OrdonnancesLoading extends OrdonnancesState {
  const OrdonnancesLoading();
}

class OrdonnancesCreated extends OrdonnancesState {
  final Prescription prescription;

  const OrdonnancesCreated(this.prescription);

  @override
  List<Object?> get props => [prescription];
}

class OrdonnancesSigned extends OrdonnancesState {
  final Prescription prescription;

  const OrdonnancesSigned(this.prescription);

  @override
  List<Object?> get props => [prescription];
}

class OrdonnancesError extends OrdonnancesState {
  final String message;

  const OrdonnancesError(this.message);

  @override
  List<Object?> get props => [message];
}
