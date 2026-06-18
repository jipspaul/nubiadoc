import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_patient.dart';
import 'package:nubia_domain/src/repositories/cabinet_patients_repository.dart';

class GetCabinetPatientUseCase {
  final CabinetPatientsRepository _repository;

  const GetCabinetPatientUseCase(this._repository);

  Future<Either<Failure, CabinetPatient>> call(String id) =>
      _repository.getById(id);
}
