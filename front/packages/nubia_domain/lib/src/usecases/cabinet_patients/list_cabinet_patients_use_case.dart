import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_patient.dart';
import 'package:nubia_domain/src/repositories/cabinet_patients_repository.dart';

class ListCabinetPatientsUseCase {
  final CabinetPatientsRepository _repository;

  const ListCabinetPatientsUseCase(this._repository);

  Future<Either<Failure, List<CabinetPatient>>> call({
    int page = 1,
    String? q,
  }) =>
      _repository.list(page: page, q: q);
}
