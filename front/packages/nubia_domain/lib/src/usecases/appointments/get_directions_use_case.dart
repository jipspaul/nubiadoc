import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/directions_result.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/appointment_repository.dart';

class GetDirectionsUseCase {
  final AppointmentRepository _repository;
  const GetDirectionsUseCase(this._repository);

  Future<Either<Failure, DirectionsResult>> call({
    required String id,
    String mode = 'car',
  }) =>
      _repository.getDirections(id, mode: mode);
}
