import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/account/account_api.dart';
import 'package:nubia_domain/src/entities/consent.dart';
import 'package:nubia_domain/src/entities/medical_questionnaire.dart';
import 'package:nubia_domain/src/entities/patient_account.dart';
import 'package:nubia_domain/src/entities/referring_doctor.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class AccountRepositoryImpl implements AccountRepository {
  final AccountApi _api;

  const AccountRepositoryImpl(this._api);

  @override
  Future<Either<Failure, PatientAccount>> getAccount() async {
    try {
      final dto = await _api.getAccount();
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, PatientAccount>> updateAccount({
    String? firstName,
    String? lastName,
    String? phone,
    DateTime? dateOfBirth,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (firstName != null) body['first_name'] = firstName;
      if (lastName != null) body['last_name'] = lastName;
      if (phone != null) body['phone'] = phone;
      // birth_date is immutable after registration; the API rejects it with
      // a 422 if present, so it must never be included in this body.
      final dto = await _api.updateAccount(body);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, HealthCoverage>> getCoverage() async {
    try {
      final dto = await _api.getCoverage();
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, HealthCoverage>> updateCoverage({
    required HealthInsuranceRegime regime,
    String? amc,
    String? numeroAdherent,
    bool thirdPartyPayment = false,
  }) async {
    try {
      final body = <String, dynamic>{
        'regime_obligatoire': _regimeToString(regime),
        'tiers_payant': thirdPartyPayment,
      };
      if (amc != null || numeroAdherent != null) {
        // L'API exige actuellement amc + numero_adherent comme champs requis
        // (non optionnels) : on envoie toujours les deux clés dès que l'une
        // est renseignée, sinon un 422 "missing field" bloque la sauvegarde
        // silencieusement (cf. issue #3434).
        body['mutuelle'] = {
          'amc': amc ?? '',
          'numero_adherent': numeroAdherent ?? '',
        };
      }
      final dto = await _api.updateCoverage(body);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, List<Dependent>>> getDependents() async {
    try {
      final dtos = await _api.getDependents();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, Dependent>> addDependent({
    required String firstName,
    required String lastName,
    DateTime? birthDate,
    required DependentRelationship relationship,
  }) async {
    try {
      final body = <String, dynamic>{
        'first_name': firstName,
        'last_name': lastName,
        'relationship': _relationshipToString(relationship),
        if (birthDate != null)
          'birth_date': birthDate.toIso8601String().substring(0, 10),
      };
      final dto = await _api.addDependent(body);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, void>> deleteDependent(String id) async {
    try {
      await _api.deleteDependent(id);
      return const Right(null);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, String>> uploadCoverageCard({
    required String filePath,
    required String mimeType,
    required CoverageCardSide side,
  }) async {
    try {
      final sideString = side == CoverageCardSide.recto ? 'recto' : 'verso';
      final documentId = await _api.uploadCoverageCard(
        filePath: filePath,
        mimeType: mimeType,
        side: sideString,
      );
      return Right(documentId);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, List<Consent>>> getConsents() async {
    try {
      final dtos = await _api.getConsents();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, ReferringDoctor?>> getReferringDoctor() async {
    try {
      final dto = await _api.getReferringDoctor();
      return Right(dto?.toDomain());
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, ReferringDoctor>> setReferringDoctor({
    String? providerId,
    required String name,
    String? specialty,
    String? phone,
    String? email,
    String? address,
  }) async {
    try {
      final body = <String, dynamic>{
        if (providerId != null) 'provider_id': providerId,
        'name': name,
        if (specialty != null) 'specialty': specialty,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (address != null) 'address': address,
      };
      final dto = await _api.setReferringDoctor(body);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, MedicalQuestionnaire>> createMedicalQuestionnaire({
    required String cabinetId,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final dto = await _api.createMedicalQuestionnaire({
        'cabinet_id': cabinetId,
        'payload': payload,
      });
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(_mapMedicalQuestionnaireError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, MedicalQuestionnaire>> patchMedicalQuestionnaire({
    required String cabinetId,
    Map<String, dynamic>? payload,
    bool submit = false,
  }) async {
    try {
      final dto = await _api.patchMedicalQuestionnaire({
        'cabinet_id': cabinetId,
        if (payload != null) 'payload': payload,
        'submit': submit,
      });
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(_mapMedicalQuestionnaireError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  /// `409`/`404` sont des signaux de contrôle attendus (brouillon
  /// existant/absent, cf. `MedicalQuestionnaireCubit`) — distincts d'une
  /// vraie erreur serveur, contrairement à `_mapError`.
  Failure _mapMedicalQuestionnaireError(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 401) return const UnauthorizedFailure();
    if (statusCode == 404) return const NotFoundFailure();
    if (statusCode == 409) {
      return const ServerFailure(
        message: 'Un brouillon existe déjà.',
        statusCode: 409,
      );
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return const NetworkFailure();
    }
    return ServerFailure(
      message: 'Erreur serveur lors de l\'enregistrement du questionnaire.',
      statusCode: statusCode,
    );
  }

  Failure _mapError(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 401) return const UnauthorizedFailure();
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return const NetworkFailure();
    }
    return ServerFailure(
      message: 'Erreur serveur lors de la mise à jour du compte.',
      statusCode: statusCode,
    );
  }

  static String _regimeToString(HealthInsuranceRegime regime) {
    switch (regime) {
      case HealthInsuranceRegime.ame:
        return 'ame';
      case HealthInsuranceRegime.css:
        return 'css';
      case HealthInsuranceRegime.regimeGeneral:
        return 'regime_general';
    }
  }

  static String _relationshipToString(DependentRelationship rel) {
    switch (rel) {
      case DependentRelationship.enfant:
        return 'enfant';
      case DependentRelationship.conjoint:
        return 'conjoint';
      case DependentRelationship.autre:
        return 'autre';
    }
  }

  @override
  Future<Either<Failure, void>> setConsent({
    required String purpose,
    required bool granted,
  }) async {
    try {
      await _api.putConsent(purpose: purpose, granted: granted);
      return const Right(null);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, AvatarImage?>> getAvatar() async {
    try {
      final result = await _api.getAvatar();
      if (result == null) return const Right(null);
      return Right(AvatarImage(bytes: result.$1, mimeType: result.$2));
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, void>> setAvatar({
    required List<int> bytes,
    required String mimeType,
  }) async {
    try {
      await _api.putAvatar(bytes: bytes, mimeType: mimeType);
      return const Right(null);
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        return const Left(ValidationFailure(
            message: 'Image invalide (JPEG/PNG/WebP, 300 Ko max).'));
      }
      return Left(_mapError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
