import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/account/account_api.dart';
import 'package:nubia_domain/src/entities/patient_account.dart';
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
    }
  }

  @override
  Future<Either<Failure, PatientAccount>> updateAccount({
    String? firstName,
    String? lastName,
    String? phone,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (firstName != null) body['first_name'] = firstName;
      if (lastName != null) body['last_name'] = lastName;
      if (phone != null) body['phone'] = phone;
      final dto = await _api.updateAccount(body);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(_mapError(e));
    }
  }

  @override
  Future<Either<Failure, HealthCoverage>> getCoverage() async {
    try {
      final dto = await _api.getCoverage();
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(_mapError(e));
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
        body['mutuelle'] = {
          if (amc != null) 'amc': amc,
          if (numeroAdherent != null) 'numero_adherent': numeroAdherent,
        };
      }
      final dto = await _api.updateCoverage(body);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(_mapError(e));
    }
  }

  @override
  Future<Either<Failure, List<Dependent>>> getDependents() async {
    try {
      final dtos = await _api.getDependents();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      return Left(_mapError(e));
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
    }
  }

  @override
  Future<Either<Failure, void>> deleteDependent(String id) async {
    try {
      await _api.deleteDependent(id);
      return const Right(null);
    } on DioException catch (e) {
      return Left(_mapError(e));
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
    }
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
}
