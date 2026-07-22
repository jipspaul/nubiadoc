import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/orthodontics/orthodontics_api.dart';
import 'package:nubia_domain/src/entities/orthodontic_treatment.dart';
import 'package:nubia_domain/src/repositories/orthodontics_repository.dart';

class OrthodonticsRepositoryImpl implements OrthodonticsRepository {
  final OrthodonticsApi _api;

  const OrthodonticsRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<OrthodonticTreatment>>> list(
    String patientId,
  ) async {
    try {
      final dtos = await _api.list(patientId);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger le suivi orthodontique.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, String>> addStep(
    String treatmentId, {
    required int stepNumber,
    required String kind,
    String? conformityNotes,
  }) async {
    try {
      final stepId = await _api.addStep(
        treatmentId,
        stepNumber: stepNumber,
        kind: kind,
        conformityNotes: conformityNotes,
      );
      return Right(stepId);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible d'ajouter l'étape.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
