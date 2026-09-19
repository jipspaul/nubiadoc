import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_data/src/remote/consent_templates/consent_template_api.dart';
import 'package:nubia_domain/src/entities/consent_template.dart';
import 'package:nubia_domain/src/entities/rendered_consent_template.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/consent_template_repository.dart';

class ConsentTemplateRepositoryImpl implements ConsentTemplateRepository {
  final ConsentTemplateApi _api;

  const ConsentTemplateRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<ConsentTemplate>>> list() async {
    try {
      final dtos = await _api.list();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les modèles de consentement.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, ({String id, int version})>> create({
    required String actCategory,
    required String title,
    required String bodyMarkdown,
  }) async {
    try {
      final result = await _api.create(
        actCategory: actCategory,
        title: title,
        bodyMarkdown: bodyMarkdown,
      );
      return Right(result);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (statusCode == 422) {
        return const Left(
          ValidationFailure(message: 'Modèle de consentement invalide.'),
        );
      }
      return Left(ServerFailure(
        message: 'Impossible de créer le modèle de consentement.',
        statusCode: statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, ({String id, int version})>> patch(
    String id, {
    String? actCategory,
    String? title,
    String? bodyMarkdown,
  }) async {
    try {
      final result = await _api.patch(
        id,
        actCategory: actCategory,
        title: title,
        bodyMarkdown: bodyMarkdown,
      );
      return Right(result);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 404) {
        return const Left(
          NotFoundFailure('Modèle de consentement introuvable.'),
        );
      }
      if (statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (statusCode == 422) {
        return const Left(
          ValidationFailure(message: 'Modèle de consentement invalide.'),
        );
      }
      return Left(ServerFailure(
        message: 'Impossible de modifier le modèle de consentement.',
        statusCode: statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, RenderedConsentTemplate>> render(
    String id, {
    required String quoteId,
  }) async {
    try {
      final dto = await _api.render(id, quoteId: quoteId);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 404) {
        return const Left(NotFoundFailure('Devis ou modèle introuvable.'));
      }
      if (statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de générer le consentement.',
        statusCode: statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
