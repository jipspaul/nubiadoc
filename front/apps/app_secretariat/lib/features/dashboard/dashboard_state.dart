import 'package:equatable/equatable.dart';

/// Résumé d'un praticien pour la carte « Praticiens aujourd'hui » (#5385) :
/// nombre de RDV du jour et présence dérivée de l'agenda (pas de champ de
/// présence dédié en base pour l'instant).
class PractitionerToday extends Equatable {
  const PractitionerToday({
    required this.practitionerId,
    required this.practitionerName,
    required this.appointmentCount,
    required this.isInConsultation,
    required this.lastAppointmentEndsAt,
  });

  final String practitionerId;
  final String practitionerName;
  final int appointmentCount;

  /// `true` si un RDV du praticien est en cours à l'instant du calcul.
  final bool isInConsultation;

  /// Fin du dernier RDV du jour — sert à afficher « Départ HHh » quand le
  /// praticien n'est pas en consultation (#5385, note #4 maquette).
  final DateTime lastAppointmentEndsAt;

  @override
  List<Object?> get props => [
        practitionerId,
        practitionerName,
        appointmentCount,
        isInConsultation,
        lastAppointmentEndsAt,
      ];
}

sealed class DashboardState extends Equatable {
  const DashboardState();

  @override
  List<Object?> get props => [];
}

final class DashboardInitial extends DashboardState {
  const DashboardInitial();
}

final class DashboardLoading extends DashboardState {
  const DashboardLoading();
}

final class DashboardLoaded extends DashboardState {
  const DashboardLoaded({
    required this.todayCount,
    required this.pendingCount,
    required this.waitingCount,
    this.practitionersToday = const [],
    this.dailyOccupancyRates = const [0, 0, 0, 0, 0, 0],
    this.freeSlotsThisWeekCount = 0,
    this.freeSlotsTomorrowMorningCount = 0,
  });

  final int todayCount;
  final int pendingCount;
  final int waitingCount;

  /// Praticiens ayant au moins un RDV aujourd'hui, dérivés de l'agenda déjà
  /// chargé (#5385) — aucun appel réseau supplémentaire.
  final List<PractitionerToday> practitionersToday;

  /// Taux d'occupation (0.0 à 1.0) du lundi au samedi, dérivés de l'agenda
  /// de la semaine déjà chargé (#5383) — aucun appel réseau supplémentaire.
  final List<double> dailyOccupancyRates;

  /// Créneaux bookables de la semaine réellement libres, rapprochés du
  /// planning réel (#5384 — la donnée `/bookable-slots` seule n'est jamais
  /// rapprochée du planning).
  final int freeSlotsThisWeekCount;

  /// Sous-ensemble de [freeSlotsThisWeekCount] démarrant demain avant midi.
  final int freeSlotsTomorrowMorningCount;

  @override
  List<Object?> get props => [
        todayCount,
        pendingCount,
        waitingCount,
        practitionersToday,
        dailyOccupancyRates,
        freeSlotsThisWeekCount,
        freeSlotsTomorrowMorningCount,
      ];
}

final class DashboardError extends DashboardState {
  const DashboardError({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}
