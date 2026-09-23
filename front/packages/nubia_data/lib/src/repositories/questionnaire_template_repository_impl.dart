import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_data/src/remote/questionnaire_templates/questionnaire_template_api.dart';
import 'package:nubia_data/src/remote/questionnaire_templates/questionnaire_template_dto.dart';
import 'package:nubia_domain/src/entities/questionnaire_question.dart';
import 'package:nubia_domain/src/entities/questionnaire_template.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/questionnaire_template_repository.dart';

class QuestionnaireTemplateRepositoryImpl
    implements QuestionnaireTemplateRepository {
  final QuestionnaireTemplateApi _api;

  const QuestionnaireTemplateRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<QuestionnaireTemplate>>> list() async {
    try {
      final dtos = await _api.list();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les modèles de questionnaire.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, ({String id, int version})>> create({
    required String title,
    required List<QuestionnaireQuestion> schema,
  }) async {
    try {
      final result = await _api.create(
        title: title,
        schema: schema.map(QuestionnaireQuestionDto.fromDomain).toList(),
      );
      return Right(result);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (statusCode == 409) {
        return const Left(ServerFailure(
          message: 'Le cabinet a déjà un modèle de questionnaire actif.',
          statusCode: 409,
        ));
      }
      if (statusCode == 422) {
        return const Left(
          ValidationFailure(message: 'Modèle de questionnaire invalide.'),
        );
      }
      return Left(ServerFailure(
        message: 'Impossible de créer le modèle de questionnaire.',
        statusCode: statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, ({String id, int version})>> patch(
    String id, {
    String? title,
    List<QuestionnaireQuestion>? schema,
  }) async {
    try {
      final result = await _api.patch(
        id,
        title: title,
        schema: schema?.map(QuestionnaireQuestionDto.fromDomain).toList(),
      );
      return Right(result);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 404) {
        return const Left(
          NotFoundFailure('Modèle de questionnaire introuvable.'),
        );
      }
      if (statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (statusCode == 422) {
        return const Left(
          ValidationFailure(message: 'Modèle de questionnaire invalide.'),
        );
      }
      return Left(ServerFailure(
        message: 'Impossible de modifier le modèle de questionnaire.',
        statusCode: statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, void>> delete(String id) async {
    try {
      await _api.delete(id);
      return const Right(null);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 404) {
        return const Left(
          NotFoundFailure('Modèle de questionnaire introuvable.'),
        );
      }
      if (statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de supprimer le modèle de questionnaire.',
        statusCode: statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
