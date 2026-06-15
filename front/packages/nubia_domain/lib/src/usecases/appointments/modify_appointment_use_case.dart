import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/appointment.dart';
import 'package:nubia_domain/src/repositories/appointment_repository.dart';

class ModifyAppointmentUseCase {
  final AppointmentRepository _repository;

  const ModifyAppointmentUseCase(this._repository);

  Future<Either<Failure, Appointment>> call({
    required String id,
    required String newSlotId,
  }) =>
      _repository.modify(id: id, newSlotId: newSlotId);
}
