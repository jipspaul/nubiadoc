import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_account.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class ListAccessRequestsUseCase {
  final AccountRepository _repository;

  const ListAccessRequestsUseCase(this._repository);

  Future<Either<Failure, List<AccessRequest>>> call() {
    return _repository.getAccessRequests();
  }
}
