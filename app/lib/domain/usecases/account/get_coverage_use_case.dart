import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';
import 'package:nubia_patient/domain/repositories/account_repository.dart';

@injectable
class GetCoverageUseCase {
  final AccountRepository _repository;

  const GetCoverageUseCase(this._repository);

  Future<Either<Failure, HealthCoverage>> call() {
    return _repository.getCoverage();
  }
}
