import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/cabinet_medical_questionnaire/cabinet_medical_questionnaire_api.dart';
import 'package:nubia_domain/src/entities/medical_questionnaire.dart';
import 'package:nubia_domain/src/repositories/cabinet_medical_questionnaire_repository.dart';

class CabinetMedicalQuestionnaireRepositoryImpl
    implements CabinetMedicalQuestionnaireRepository {
  final CabinetMedicalQuestionnaireApi _api;

  const CabinetMedicalQuestionnaireRepositoryImpl(this._api);

  @override
  Future<Either<Failure, MedicalQuestionnaire?>> get(String patientId) async {
    try {
      final dto = await _api.get(patientId);
      return Right(dto?.toDomain());
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, MedicalQuestionnaire>> review(
    String patientId,
  ) async {
    try {
      final dto = await _api.review(patientId);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        return const Left(ClinicalAccessDenied());
      }
      if (e.response?.statusCode == 409) {
        return const Left(
          ValidationFailure(message: 'Déjà validé et importé.'),
        );
      }
      return Left(_mapError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  Failure _mapError(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 401) return const UnauthorizedFailure();
    if (statusCode == 404) return const NotFoundFailure('Patient introuvable.');
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return const NetworkFailure();
    }
    return ServerFailure(
      message: 'Impossible de charger le questionnaire médical.',
      statusCode: statusCode,
    );
  }
}
