import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/domain/repositories/appointment_repository.dart';

@injectable
class GetAppointmentHistoryUseCase {
  final AppointmentRepository _repository;

  const GetAppointmentHistoryUseCase(this._repository);

  Future<Either<Failure, List<Appointment>>> call({int page = 1}) =>
      _repository.getHistory(page: page);
}
