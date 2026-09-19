import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_correspondent.dart';
import 'package:nubia_domain/src/repositories/cabinet_correspondents_repository.dart';

class ListCabinetCorrespondentsUseCase {
  final CabinetCorrespondentsRepository _repository;

  const ListCabinetCorrespondentsUseCase(this._repository);

  Future<Either<Failure, List<CabinetCorrespondent>>> call() =>
      _repository.list();
}
