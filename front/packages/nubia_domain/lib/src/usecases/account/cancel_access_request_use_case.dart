import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class CancelAccessRequestUseCase {
  final AccountRepository _repository;
  const CancelAccessRequestUseCase(this._repository);

  Future<Either<Failure, void>> call(String id) =>
      _repository.cancelAccessRequest(id);
}
