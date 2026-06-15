import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/appointment.dart';
import 'package:nubia_domain/src/repositories/appointment_repository.dart';

class GetAppointmentHistoryUseCase {
  final AppointmentRepository _repository;

  const GetAppointmentHistoryUseCase(this._repository);

  Future<Either<Failure, List<Appointment>>> call({int page = 1}) =>
      _repository.getHistory(page: page);
}
