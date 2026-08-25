import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/patient_account.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class AcceptAccessRequestUseCase {
  final AccountRepository _repository;
  const AcceptAccessRequestUseCase(this._repository);

  Future<Either<Failure, AccessRequest>> call(String id) =>
      _repository.acceptAccessRequest(id);
}
