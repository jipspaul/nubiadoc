import 'package:dartz/dartz.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';

/// PORT — account boundary (profil patient, couverture, proches).
abstract class AccountRepository {
  Future<Either<Failure, PatientAccount>> getAccount();

  Future<Either<Failure, PatientAccount>> updateAccount({
    String? firstName,
    String? lastName,
    String? phone,
  });

  Future<Either<Failure, HealthCoverage>> getCoverage();

  Future<Either<Failure, HealthCoverage>> updateCoverage({
    required HealthInsuranceRegime regime,
    String? amc,
    String? numeroAdherent,
    bool thirdPartyPayment = false,
  });

  Future<Either<Failure, List<Dependent>>> getDependents();

  Future<Either<Failure, Dependent>> addDependent({
    required String firstName,
    required String lastName,
    DateTime? birthDate,
    required DependentRelationship relationship,
  });

  Future<Either<Failure, void>> deleteDependent(String id);
}
