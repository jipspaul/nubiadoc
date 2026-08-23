import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class HomeState extends Equatable {
  const HomeState();

  @override
  List<Object?> get props => [];
}

final class HomeInitial extends HomeState {
  const HomeInitial();
}

final class HomeLoading extends HomeState {
  const HomeLoading();
}

final class HomeLoaded extends HomeState {
  final DashboardSummary summary;

  /// Plan de traitement actif à afficher dans la carte « Mon suivi »
  /// (#5202) — `null` si le patient n'a aucun plan en cours avec des
  /// données de progression.
  final PatientTreatmentPlan? treatmentPlan;

  const HomeLoaded(this.summary, {this.treatmentPlan});

  @override
  List<Object?> get props => [summary, treatmentPlan];
}

final class HomeError extends HomeState {
  final String message;

  const HomeError(this.message);

  @override
  List<Object?> get props => [message];
}
