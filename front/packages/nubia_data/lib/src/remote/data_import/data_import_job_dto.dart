import 'package:nubia_domain/src/entities/data_import_job.dart';

class DataImportReportLineDto {
  const DataImportReportLineDto({
    required this.line,
    this.externalRef,
    required this.action,
    this.message,
  });

  final int line;
  final String? externalRef;
  final String action;
  final String? message;

  factory DataImportReportLineDto.fromJson(Map<String, dynamic> json) =>
      DataImportReportLineDto(
        line: json['line'] as int,
        externalRef: json['external_ref'] as String?,
        action: json['action'] as String,
        message: json['message'] as String?,
      );

  DataImportReportLine toDomain() => DataImportReportLine(
        line: line,
        externalRef: externalRef,
        action: action,
        message: message,
      );
}

class DataImportReportDto {
  const DataImportReportDto({
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
  final List<DataImportReportLineDto> lines;

  factory DataImportReportDto.fromJson(Map<String, dynamic> json) =>
      DataImportReportDto(
        mode: json['mode'] as String,
        total: json['total'] as int,
        created: json['created'] as int?,
        updated: json['updated'] as int?,
        unchanged: json['unchanged'] as int?,
        errors: json['errors'] as int,
        lines: (json['lines'] as List<dynamic>? ?? [])
            .map((e) =>
                DataImportReportLineDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  DataImportReport toDomain() => DataImportReport(
        mode: mode,
        total: total,
        created: created,
        updated: updated,
        unchanged: unchanged,
        errors: errors,
        lines: lines.map((e) => e.toDomain()).toList(),
      );
}

DataImportKind _kindFromWire(String raw) => switch (raw) {
      'csv_appointments' => DataImportKind.csvAppointments,
      _ => DataImportKind.csvPatients,
    };

DataImportStatus _statusFromWire(String raw) => switch (raw) {
      'running' => DataImportStatus.running,
      'completed' => DataImportStatus.completed,
      'failed' => DataImportStatus.failed,
      _ => DataImportStatus.pending,
    };

/// Miroir de `ImportJobView` (`api/src/data_import/mod.rs`).
class DataImportJobDto {
  const DataImportJobDto({
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
  final String kind;
  final String sourceSystem;
  final String? fileName;
  final String status;
  final int totalCount;
  final int importedCount;
  final int skippedCount;
  final int errorCount;
  final String? startedAt;
  final String? finishedAt;
  final String? dryRunAt;
  final String createdAt;
  final DataImportReportDto report;

  factory DataImportJobDto.fromJson(Map<String, dynamic> json) =>
      DataImportJobDto(
        id: json['id'] as String,
        kind: json['kind'] as String,
        sourceSystem: json['source_system'] as String,
        fileName: json['file_name'] as String?,
        status: json['status'] as String,
        totalCount: json['total_count'] as int,
        importedCount: json['imported_count'] as int,
        skippedCount: json['skipped_count'] as int,
        errorCount: json['error_count'] as int,
        startedAt: json['started_at'] as String?,
        finishedAt: json['finished_at'] as String?,
        dryRunAt: json['dry_run_at'] as String?,
        createdAt: json['created_at'] as String,
        report: DataImportReportDto.fromJson(
            json['report'] as Map<String, dynamic>),
      );

  DataImportJob toDomain() => DataImportJob(
        id: id,
        kind: _kindFromWire(kind),
        sourceSystem: sourceSystem,
        fileName: fileName,
        status: _statusFromWire(status),
        totalCount: totalCount,
        importedCount: importedCount,
        skippedCount: skippedCount,
        errorCount: errorCount,
        startedAt: startedAt == null ? null : DateTime.parse(startedAt!),
        finishedAt: finishedAt == null ? null : DateTime.parse(finishedAt!),
        dryRunAt: dryRunAt == null ? null : DateTime.parse(dryRunAt!),
        createdAt: DateTime.parse(createdAt),
        report: report.toDomain(),
      );
}
