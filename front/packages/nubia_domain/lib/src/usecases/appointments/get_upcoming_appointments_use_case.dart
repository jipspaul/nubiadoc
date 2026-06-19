import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/appointment.dart';
import 'package:nubia_domain/src/repositories/appointment_repository.dart';

class GetUpcomingAppointmentsUseCase {
  final AppointmentRepository _repository;

  const GetUpcomingAppointmentsUseCase(this._repository);

  Future<Either<Failure, List<Appointment>>> call() =>
      _repository.getUpcoming();
}
