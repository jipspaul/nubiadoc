import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/appointment.dart';
import 'package:nubia_domain/src/repositories/appointment_repository.dart';

class CheckinAppointmentUseCase {
  final AppointmentRepository _repository;

  const CheckinAppointmentUseCase(this._repository);

  Future<Either<Failure, Appointment>> call(String id) =>
      _repository.checkin(id);
}
