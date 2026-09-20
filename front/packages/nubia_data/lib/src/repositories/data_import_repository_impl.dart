import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_data/src/remote/data_import/data_import_api.dart';
import 'package:nubia_data/src/remote/data_import/data_import_job_dto.dart';
import 'package:nubia_domain/src/entities/data_import_job.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/data_import_repository.dart';

const _kindWire = {
  DataImportKind.csvPatients: 'csv_patients',
  DataImportKind.csvAppointments: 'csv_appointments',
};

class DataImportRepositoryImpl implements DataImportRepository {
  const DataImportRepositoryImpl(this._api);

  final DataImportApi _api;

  @override
  Future<Either<Failure, DataImportJob>> upload({
    required DataImportKind kind,
    required List<int> bytes,
    required String filename,
  }) =>
      _call(
        () => _api.upload(
          kind: _kindWire[kind]!,
          bytes: bytes,
          filename: filename,
        ),
        "Impossible d'envoyer le fichier.",
      );

  @override
  Future<Either<Failure, DataImportJob>> dryRun(String jobId) => _call(
        () => _api.dryRun(jobId),
        "Impossible de lancer l'analyse à blanc.",
      );

  @override
  Future<Either<Failure, DataImportJob>> run(String jobId) => _call(
        () => _api.run(jobId),
        "Impossible de lancer l'import.",
      );

  @override
  Future<Either<Failure, DataImportJob>> getStatus(String jobId) => _call(
        () => _api.getStatus(jobId),
        "Impossible de récupérer le statut de l'import.",
      );

  Future<Either<Failure, DataImportJob>> _call(
    Future<DataImportJobDto> Function() request,
    String defaultMessage,
  ) async {
    try {
      final dto = await request();
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(_mapError(e, defaultMessage));
    } catch (_) {
      return const Left(ParseFailure());
    }
  }

  Failure _mapError(DioException e, String defaultMessage) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 401) return const UnauthorizedFailure();
    if (statusCode == 404) return const NotFoundFailure('Import introuvable.');
    final code = e.response?.data is Map
        ? (e.response!.data as Map)['code'] as String?
        : null;
    if (statusCode == 409 && code == 'invalid_status') {
      return const ValidationFailure(
        message: 'Un import est déjà en cours pour ce job.',
      );
    }
    if (statusCode == 422 && code == 'validation_error') {
      return const ValidationFailure(message: 'Fichier ou format invalide.');
    }
    if (statusCode == 503 && code == 'kms_not_configured') {
      return ServerFailure(
        message: 'Service de chiffrement indisponible. Réessayez plus tard.',
        statusCode: statusCode,
      );
    }
    return ServerFailure(message: defaultMessage, statusCode: statusCode);
  }
}
