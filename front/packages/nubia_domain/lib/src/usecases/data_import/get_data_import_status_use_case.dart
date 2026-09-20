import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/data_import_job.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/data_import_repository.dart';

class GetDataImportStatusUseCase {
  const GetDataImportStatusUseCase(this._repository);

  final DataImportRepository _repository;

  Future<Either<Failure, DataImportJob>> call(String jobId) =>
      _repository.getStatus(jobId);
}
