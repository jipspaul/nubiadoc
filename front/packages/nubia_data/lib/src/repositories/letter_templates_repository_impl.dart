import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/letter_templates/letter_templates_api.dart';
import 'package:nubia_domain/src/entities/letter_template.dart';
import 'package:nubia_domain/src/repositories/letter_templates_repository.dart';

class LetterTemplatesRepositoryImpl implements LetterTemplatesRepository {
  final LetterTemplatesApi _api;

  const LetterTemplatesRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<LetterTemplate>>> list() async {
    try {
      final dtos = await _api.list();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les modèles de courrier.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
