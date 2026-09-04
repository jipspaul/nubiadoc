import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_appointment.dart';
import 'package:nubia_domain/src/repositories/cabinet_appointments_repository.dart';

/// `POST /v1/cabinet/appointments/:id/checkin` (#6411) — le secrétariat
/// marque un patient arrivé au comptoir, action primaire du volet détail
/// agenda (design-v2).
class CabinetCheckinAppointmentUseCase {
  final CabinetAppointmentsRepository _repository;

  const CabinetCheckinAppointmentUseCase(this._repository);

  Future<Either<Failure, CabinetAppointment>> call(String id) =>
      _repository.checkin(id);
}
