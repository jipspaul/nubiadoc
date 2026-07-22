import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/orthodontic_treatment.dart';
import 'package:nubia_domain/src/repositories/orthodontics_repository.dart';

class ListOrthodonticTreatmentsUseCase {
  final OrthodonticsRepository _repository;

  const ListOrthodonticTreatmentsUseCase(this._repository);

  Future<Either<Failure, List<OrthodonticTreatment>>> call(String patientId) =>
      _repository.list(patientId);
}
