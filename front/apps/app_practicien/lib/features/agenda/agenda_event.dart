import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

abstract class AgendaEvent extends Equatable {
  const AgendaEvent();

  @override
  List<Object?> get props => [];
}

class AgendaLoadRequested extends AgendaEvent {
  const AgendaLoadRequested({required this.weekStart});
  final DateTime weekStart;

  @override
  List<Object?> get props => [weekStart];
}

class AgendaWeekChanged extends AgendaEvent {
  const AgendaWeekChanged({required this.weekStart});
  final DateTime weekStart;

  @override
  List<Object?> get props => [weekStart];
}

class AgendaAppointmentConfirmRequested extends AgendaEvent {
  const AgendaAppointmentConfirmRequested({required this.appointmentId});
  final String appointmentId;

  @override
  List<Object?> get props => [appointmentId];
}

/// La page a consommé startedConsultationId (navigation faite) — remet le
/// champ à null pour ne pas re-naviguer au prochain rebuild.
class AgendaStartedConsultationConsumed extends AgendaEvent {
  const AgendaStartedConsultationConsumed();
}

class AgendaConsultationStartRequested extends AgendaEvent {
  const AgendaConsultationStartRequested({required this.appointmentId});
  final String appointmentId;

  @override
  List<Object?> get props => [appointmentId];
}

class TogglePastIncluded extends AgendaEvent {
  const TogglePastIncluded();
}

/// #4088 — création d'une série de RDV liés (ortho, parodonto, chirurgie
/// multi-séances) via `POST /v1/cabinet/appointments/series`.
class AgendaSeriesCreateRequested extends AgendaEvent {
  const AgendaSeriesCreateRequested({
    required this.practitionerId,
    required this.patientId,
    required this.motif,
    required this.occurrences,
  });
  final String practitionerId;
  final String patientId;
  final String motif;
  final List<AppointmentSeriesOccurrence> occurrences;

  @override
  List<Object?> get props => [practitionerId, patientId, motif, occurrences];
}

/// La page a consommé [AgendaLoaded.seriesAppointmentsCreated] (snackbar
/// affiché) — remet le champ à null pour ne pas ré-afficher au prochain
/// rebuild (même pattern que [AgendaStartedConsultationConsumed]).
class AgendaSeriesCreatedConsumed extends AgendaEvent {
  const AgendaSeriesCreatedConsumed();
}
