import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/consent.dart';
import 'package:nubia_domain/src/entities/medical_questionnaire.dart';
import 'package:nubia_domain/src/entities/patient_account.dart';
import 'package:nubia_domain/src/entities/referring_doctor.dart';

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

  /// GET /v1/account/referring-doctor — Right(null) si aucun médecin déclaré.
  Future<Either<Failure, ReferringDoctor?>> getReferringDoctor();

  /// PUT /v1/account/referring-doctor — [providerId] si le médecin est un
  /// praticien Nubia existant, sinon coordonnées saisies librement (le
  /// médecin déclaré n'a pas besoin d'être inscrit sur Nubia).
  Future<Either<Failure, ReferringDoctor>> setReferringDoctor({
    String? providerId,
    required String name,
    String? specialty,
    String? phone,
    String? email,
    String? address,
  });

  /// POST /v1/account/medical-questionnaire — crée un brouillon pour
  /// [cabinetId]. `ServerFailure(statusCode: 409)` si un brouillon existe déjà.
  Future<Either<Failure, MedicalQuestionnaire>> createMedicalQuestionnaire({
    required String cabinetId,
    required Map<String, dynamic> payload,
  });

  /// PATCH /v1/account/medical-questionnaire — modifie le brouillon existant
  /// pour [cabinetId] et/ou le soumet (`submit: true`).
  /// `NotFoundFailure` si aucun brouillon n'existe pour ce cabinet.
  Future<Either<Failure, MedicalQuestionnaire>> patchMedicalQuestionnaire({
    required String cabinetId,
    Map<String, dynamic>? payload,
    bool submit = false,
  });
}

/// Photo de profil : octets + type MIME.
class AvatarImage {
  final List<int> bytes;
  final String mimeType;
  const AvatarImage({required this.bytes, required this.mimeType});
}

enum CoverageCardSide { recto, verso }
