import 'package:equatable/equatable.dart';

sealed class DashboardEvent extends Equatable {
  const DashboardEvent();

  @override
  List<Object?> get props => [];
}

final class DashboardLoadRequested extends DashboardEvent {
  const DashboardLoadRequested();
}

/// « Démarrer la consultation » du hero « Patient suivant » (#6241) : le
/// hero connaît le RDV en salle d'attente (`nextPatientAppointmentId`), donc
/// démarre réellement la séance au lieu de renvoyer vers une liste générique.
final class DashboardConsultationStartRequested extends DashboardEvent {
  const DashboardConsultationStartRequested({required this.appointmentId});

  final String appointmentId;

  @override
  List<Object?> get props => [appointmentId];
}

/// La page a consommé `startedConsultationId` (navigation faite) — remet le
/// champ à `null` pour ne pas re-déclencher la navigation au rebuild suivant.
final class DashboardStartedConsultationConsumed extends DashboardEvent {
  const DashboardStartedConsultationConsumed();
}
