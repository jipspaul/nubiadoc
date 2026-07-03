import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class DeleteDependentUseCase {
  final AccountRepository _repository;
  const DeleteDependentUseCase(this._repository);

  Future<Either<Failure, void>> call(String id) =>
      _repository.deleteDependent(id);
}
