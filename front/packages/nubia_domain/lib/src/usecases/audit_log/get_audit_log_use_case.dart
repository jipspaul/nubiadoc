import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/audit_log_entry.dart';
import 'package:nubia_domain/src/repositories/audit_log_repository.dart';

class GetAuditLogUseCase {
  final AuditLogRepository _repository;

  const GetAuditLogUseCase(this._repository);

  Future<Either<Failure, List<AuditLogEntry>>> call({
    DateTime? from,
    DateTime? to,
    String? entity,
  }) =>
      _repository.getAuditLog(from: from, to: to, entity: entity);
}
