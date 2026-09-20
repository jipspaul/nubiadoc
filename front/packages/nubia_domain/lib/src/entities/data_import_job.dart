import 'package:equatable/equatable.dart';

/// Format/parseur d'un job de reprise de données (DP-F14, #7179/#7178).
/// Valeurs alignées sur `data_import_job.kind` (`api/src/data_import/source.rs`).
enum DataImportKind { csvPatients, csvAppointments }

/// Statut d'un job de reprise — `data_import_job.status`.
enum DataImportStatus { pending, running, completed, failed }

/// Issue d'une ligne du rapport. `action` reprend les valeurs wire de
/// `LineAction` côté API (`created`/`updated`/`unchanged`/`error`) pour le
/// dry-run et le run ; le rapport d'upload ne liste que les lignes `error`.
class DataImportReportLine extends Equatable {
  const DataImportReportLine({
    required this.line,
    this.externalRef,
    required this.action,
    this.message,
  });

  final int line;
  final String? externalRef;
  final String action;
  final String? message;

  @override
  List<Object?> get props => [line, externalRef, action, message];
}

/// Rapport d'un job à un instant donné : `mode` distingue l'aperçu à
/// l'upload (`upload`, erreurs seules), l'analyse à blanc (`dry_run`) et
/// l'import effectif (`run`).
class DataImportReport extends Equatable {
  const DataImportReport({
    required this.mode,
    required this.total,
    this.created,
    this.updated,
    this.unchanged,
    required this.errors,
    required this.lines,
  });

  final String mode;
  final int total;
  final int? created;
  final int? updated;
  final int? unchanged;
  final int errors;
  final List<DataImportReportLine> lines;

  @override
  List<Object?> get props =>
      [mode, total, created, updated, unchanged, errors, lines];
}

/// Job de reprise de données — `POST /v1/cabinet/imports` (#7179).
class DataImportJob extends Equatable {
  const DataImportJob({
    required this.id,
    required this.kind,
    required this.sourceSystem,
    this.fileName,
    required this.status,
    required this.totalCount,
    required this.importedCount,
    required this.skippedCount,
    required this.errorCount,
    this.startedAt,
    this.finishedAt,
    this.dryRunAt,
    required this.createdAt,
    required this.report,
  });

  final String id;
  final DataImportKind kind;
  final String sourceSystem;
  final String? fileName;
  final DataImportStatus status;
  final int totalCount;
  final int importedCount;
  final int skippedCount;
  final int errorCount;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime? dryRunAt;
  final DateTime createdAt;
  final DataImportReport report;

  @override
  List<Object?> get props => [
        id,
        kind,
        sourceSystem,
        fileName,
        status,
        totalCount,
        importedCount,
        skippedCount,
        errorCount,
        startedAt,
        finishedAt,
        dryRunAt,
        createdAt,
        report,
      ];
}
