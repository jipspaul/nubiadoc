import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/domain/repositories/appointment_repository.dart';

@injectable
class ModifyAppointmentUseCase {
  final AppointmentRepository _repository;

  const ModifyAppointmentUseCase(this._repository);

  Future<Either<Failure, Appointment>> call({
    required String id,
    required String newSlotId,
  }) =>
      _repository.modify(id: id, newSlotId: newSlotId);
}
