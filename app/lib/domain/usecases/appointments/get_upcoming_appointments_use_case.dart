import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/domain/repositories/appointment_repository.dart';

@injectable
class GetUpcomingAppointmentsUseCase {
  final AppointmentRepository _repository;

  const GetUpcomingAppointmentsUseCase(this._repository);

  Future<Either<Failure, List<Appointment>>> call() =>
      _repository.getUpcoming();
}
