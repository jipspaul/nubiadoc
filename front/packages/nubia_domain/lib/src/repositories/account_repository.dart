import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/consent.dart';
import 'package:nubia_domain/src/entities/patient_account.dart';

/// PORT — account boundary (profil patient, couverture, proches, consentements).
abstract class AccountRepository {
  Future<Either<Failure, PatientAccount>> getAccount();

  Future<Either<Failure, PatientAccount>> updateAccount({
    String? firstName,
    String? lastName,
    String? phone,
    DateTime? dateOfBirth,
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

  /// Upload a coverage card image (recto or verso).
  ///
  /// Returns the created document id on success.
  Future<Either<Failure, String>> uploadCoverageCard({
    required String filePath,
    required String mimeType,
    required CoverageCardSide side,
  });

  Future<Either<Failure, List<Consent>>> getConsents();

  /// PUT /v1/account/consents/{purpose} — donne ou révoque un consentement.
  Future<Either<Failure, void>> setConsent({
    required String purpose,
    required bool granted,
  });

  /// GET /v1/account/avatar — photo de profil (null si aucune).
  Future<Either<Failure, AvatarImage?>> getAvatar();

  /// PUT /v1/account/avatar — photo de profil (image ≤ 300 Ko).
  Future<Either<Failure, void>> setAvatar({
    required List<int> bytes,
    required String mimeType,
  });
}

/// Photo de profil : octets + type MIME.
class AvatarImage {
  final List<int> bytes;
  final String mimeType;
  const AvatarImage({required this.bytes, required this.mimeType});
}

enum CoverageCardSide { recto, verso }
