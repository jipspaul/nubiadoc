import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/cr_templates/cr_template_api.dart';
import 'package:nubia_domain/src/entities/cr_template.dart';
import 'package:nubia_domain/src/repositories/cr_template_repository.dart';

class CrTemplateRepositoryImpl implements CrTemplateRepository {
  final CrTemplateApi _api;

  const CrTemplateRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<CrTemplate>>> listCrTemplates() async {
    try {
      final dtos = await _api.listCrTemplates();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les modèles de compte rendu.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
