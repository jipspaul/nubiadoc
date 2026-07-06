import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/appointment_preparation.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/appointment_repository.dart';

class GetAppointmentPreparationUseCase {
  final AppointmentRepository _repository;
  const GetAppointmentPreparationUseCase(this._repository);

  Future<Either<Failure, AppointmentPreparation>> call(String id) =>
      _repository.getPreparation(id);
}
