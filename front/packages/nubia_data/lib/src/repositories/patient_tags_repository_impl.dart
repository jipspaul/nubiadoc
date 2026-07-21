import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/patient_tags/patient_tags_api.dart';
import 'package:nubia_domain/src/entities/patient_tag.dart';
import 'package:nubia_domain/src/repositories/patient_tags_repository.dart';

class PatientTagsRepositoryImpl implements PatientTagsRepository {
  final PatientTagsApi _api;

  const PatientTagsRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<PatientTag>>> list(String patientId) async {
    try {
      final dtos = await _api.list(patientId);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les étiquettes.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, PatientTag>> create(
    String patientId, {
    required String label,
    String? color,
  }) async {
    try {
      final dto = await _api.create(patientId, label: label, color: color);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        return const Left(
          ValidationFailure(
              message: "Le libellé de l'étiquette est obligatoire."),
        );
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de créer l'étiquette.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, void>> delete(String patientId, String tagId) async {
    try {
      await _api.delete(patientId, tagId);
      return const Right(null);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Étiquette introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de supprimer l'étiquette.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
