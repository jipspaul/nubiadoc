import 'package:equatable/equatable.dart';

/// Une occurrence à créer via `POST /v1/cabinet/appointments/series`
/// (#4088) — voir [CreateAppointmentSeriesUseCase].
class AppointmentSeriesOccurrence extends Equatable {
  final DateTime startsAt;
  final DateTime endsAt;

  const AppointmentSeriesOccurrence({
    required this.startsAt,
    required this.endsAt,
  });

  @override
  List<Object?> get props => [startsAt, endsAt];
}

/// Un RDV effectivement créé au sein d'une série (réponse du back).
class CreatedAppointmentSeriesItem extends Equatable {
  final String id;
  final int recurrenceIndex;
  final DateTime startsAt;
  final DateTime endsAt;

  const CreatedAppointmentSeriesItem({
    required this.id,
    required this.recurrenceIndex,
    required this.startsAt,
    required this.endsAt,
  });

  @override
  List<Object?> get props => [id, recurrenceIndex, startsAt, endsAt];
}

/// Résultat de la création d'une série de RDV liés (ortho, parodonto,
/// chirurgie multi-séances) — `recurrence_id` commun à tous les
/// [appointments].
class CreatedAppointmentSeries extends Equatable {
  final String recurrenceId;
  final List<CreatedAppointmentSeriesItem> appointments;

  const CreatedAppointmentSeries({
    required this.recurrenceId,
    required this.appointments,
  });

  @override
  List<Object?> get props => [recurrenceId, appointments];
}
