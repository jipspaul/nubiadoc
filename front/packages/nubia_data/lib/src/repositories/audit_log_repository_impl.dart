import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/audit_log/audit_log_api.dart';
import 'package:nubia_domain/src/entities/audit_log_entry.dart';
import 'package:nubia_domain/src/repositories/audit_log_repository.dart';

class AuditLogRepositoryImpl implements AuditLogRepository {
  final AuditLogApi _api;

  const AuditLogRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<AuditLogEntry>>> getAuditLog({
    DateTime? from,
    DateTime? to,
    String? entity,
  }) async {
    try {
      final dtos = await _api.getAuditLog(from: from, to: to, entity: entity);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de charger le journal d'accès.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
