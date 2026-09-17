import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_appointment.dart';
import 'package:nubia_domain/src/repositories/cabinet_appointments_repository.dart';

/// `POST /v1/cabinet/appointments/:id/cancel` (#7099) — le secrétariat (ou
/// le praticien) annule un RDV pour le compte du patient, geste le plus
/// courant du comptoir (le patient téléphone pour annuler).
class CancelCabinetAppointmentUseCase {
  final CabinetAppointmentsRepository _repository;

  const CancelCabinetAppointmentUseCase(this._repository);

  Future<Either<Failure, CabinetAppointment>> call(String id) =>
      _repository.cancel(id);
}
