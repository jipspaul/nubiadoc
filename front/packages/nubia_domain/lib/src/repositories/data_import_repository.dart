import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/data_import_job.dart';
import 'package:nubia_domain/src/error/failure.dart';

abstract class DataImportRepository {
  /// `POST /v1/cabinet/imports` (#7179) : upload d'un fichier de reprise,
  /// parsé pour validation (aucune écriture métier tant que [run] n'est pas
  /// appelé).
  Future<Either<Failure, DataImportJob>> upload({
    required DataImportKind kind,
    required List<int> bytes,
    required String filename,
  });

  /// `POST /v1/cabinet/imports/:id/dry-run` : analyse à blanc, rapport
  /// ligne à ligne, aucune écriture (transaction annulée côté API).
  Future<Either<Failure, DataImportJob>> dryRun(String jobId);

  /// `POST /v1/cabinet/imports/:id/run` : import effectif, idempotent.
  Future<Either<Failure, DataImportJob>> run(String jobId);

  /// `GET /v1/cabinet/imports/:id` : statut courant (polling pendant le run).
  Future<Either<Failure, DataImportJob>> getStatus(String jobId);
}
