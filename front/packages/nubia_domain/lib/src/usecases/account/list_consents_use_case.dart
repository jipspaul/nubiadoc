import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/consent.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class ListConsentsUseCase {
  final AccountRepository _repository;

  const ListConsentsUseCase(this._repository);

  Future<Either<Failure, List<Consent>>> call() {
    return _repository.getConsents();
  }
}
