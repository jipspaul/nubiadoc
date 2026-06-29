import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_account.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class UpdateCoverageUseCase {
  final AccountRepository _repository;

  const UpdateCoverageUseCase(this._repository);

  Future<Either<Failure, HealthCoverage>> call({
    required HealthInsuranceRegime regime,
    String? amc,
    String? numeroAdherent,
    bool thirdPartyPayment = false,
  }) {
    return _repository.updateCoverage(
      regime: regime,
      amc: amc,
      numeroAdherent: numeroAdherent,
      thirdPartyPayment: thirdPartyPayment,
    );
  }
}
