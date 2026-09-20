import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/data_import_job.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/data_import_repository.dart';

class UploadDataImportUseCase {
  const UploadDataImportUseCase(this._repository);

  final DataImportRepository _repository;

  Future<Either<Failure, DataImportJob>> call({
    required DataImportKind kind,
    required List<int> bytes,
    required String filename,
  }) =>
      _repository.upload(kind: kind, bytes: bytes, filename: filename);
}
