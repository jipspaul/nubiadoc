import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/cabinet_correspondents_repository.dart';

class DeleteCabinetCorrespondentUseCase {
  final CabinetCorrespondentsRepository _repository;

  const DeleteCabinetCorrespondentUseCase(this._repository);

  Future<Either<Failure, void>> call(String id) => _repository.delete(id);
}
