import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class SetConsentUseCase {
  final AccountRepository _repository;
  const SetConsentUseCase(this._repository);

  Future<Either<Failure, void>> call({
    required String purpose,
    required bool granted,
  }) =>
      _repository.setConsent(purpose: purpose, granted: granted);
}
