import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_account.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class GetAccountUseCase {
  final AccountRepository _repository;

  const GetAccountUseCase(this._repository);

  Future<Either<Failure, PatientAccount>> call() {
    return _repository.getAccount();
  }
}
