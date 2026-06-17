import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_account.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class ListDependentsUseCase {
  final AccountRepository _repository;

  const ListDependentsUseCase(this._repository);

  Future<Either<Failure, List<Dependent>>> call() {
    return _repository.getDependents();
  }
}
