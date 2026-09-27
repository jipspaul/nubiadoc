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

  /// Détail du prochain RDV (date, praticien, motif, adresse) pour la carte
  /// héros (#5198) — `null` si aucun RDV à venir ou si le chargement a
  /// échoué (la carte héros retombe alors sur son état par défaut).
  final Appointment? nextAppointment;

  /// Nombre d'ordonnances non brouillon (signées/envoyées) — sous-titre
  /// d'état de la tuile « Mes ordonnances » (#6963). `null` si le
  /// chargement a échoué : le sous-titre est alors omis plutôt que de
  /// mentir (#6215).
  final int? activePrescriptionsCount;

  /// Nombre total de documents du coffre — sous-titre de la tuile « Mes
  /// documents » (#6963). `null` si le chargement a échoué.
  final int? documentsCount;

  /// Pharmacie déclarée par le patient — sous-titre de la tuile « Ma
  /// pharmacie » (#6963). `null` si aucune pharmacie déclarée ou si le
  /// chargement a échoué.
  final Pharmacy? pharmacy;

  /// Nombre de proches liés au compte — sous-titre de la tuile « Mes
  /// proches » (#6963). `null` si le chargement a échoué.
  final int? dependentsCount;

  const HomeLoaded(
    this.summary, {
    this.treatmentPlan,
    this.nextAppointment,
    this.activePrescriptionsCount,
    this.documentsCount,
    this.pharmacy,
    this.dependentsCount,
  });

  @override
  List<Object?> get props => [
        summary,
        treatmentPlan,
        nextAppointment,
        activePrescriptionsCount,
        documentsCount,
        pharmacy,
        dependentsCount,
      ];
}

final class HomeError extends HomeState {
  final String message;

  const HomeError(this.message);

  @override
  List<Object?> get props => [message];
}
