import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_appointment.dart';
import 'package:nubia_domain/src/entities/appointment_series.dart';

abstract class CabinetAppointmentsRepository {
  Future<Either<Failure, List<CabinetAppointment>>> list({int page = 1});
  Future<Either<Failure, CabinetAppointment>> getById(String id);
  Future<Either<Failure, CabinetAppointment>> create(
      CabinetAppointment appointment);
  Future<Either<Failure, CabinetAppointment>> update(
      CabinetAppointment appointment);
  Future<Either<Failure, CabinetAppointment>> confirm(String id);
  Future<Either<Failure, CabinetAppointment>> reschedule(
      String id, DateTime newStartsAt);

  /// `POST /v1/cabinet/appointments/series` (#4088) — crée N RDV liés par un
  /// `recurrence_id` commun en une seule transaction (ortho, parodonto,
  /// chirurgie multi-séances).
  Future<Either<Failure, CreatedAppointmentSeries>> createSeries({
    required String practitionerId,
    required String patientId,
    String? motif,
    required List<AppointmentSeriesOccurrence> occurrences,
  });
}
