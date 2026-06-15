import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_account.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class GetCoverageUseCase {
  final AccountRepository _repository;

  const GetCoverageUseCase(this._repository);

  Future<Either<Failure, HealthCoverage>> call() {
    return _repository.getCoverage();
  }
}
