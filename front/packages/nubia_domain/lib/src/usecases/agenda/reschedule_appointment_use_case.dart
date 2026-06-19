import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_appointment.dart';
import 'package:nubia_domain/src/repositories/cabinet_appointments_repository.dart';

class RescheduleAppointmentUseCase {
  final CabinetAppointmentsRepository _repository;

  const RescheduleAppointmentUseCase(this._repository);

  Future<Either<Failure, CabinetAppointment>> call(
          String id, DateTime newStartsAt) =>
      _repository.reschedule(id, newStartsAt);
}
