import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/audit_log_entry.dart';

abstract class AuditLogRepository {
  /// GET /v1/cabinet/audit-log (#4155). `from`/`to` bornent `occurred_at`
  /// (jour entier, inclusif) ; `entity` filtre exact.
  Future<Either<Failure, List<AuditLogEntry>>> getAuditLog({
    DateTime? from,
    DateTime? to,
    String? entity,
  });
}
