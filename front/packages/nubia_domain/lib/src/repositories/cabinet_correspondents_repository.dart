import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_correspondent.dart';

abstract class CabinetCorrespondentsRepository {
  Future<Either<Failure, List<CabinetCorrespondent>>> list();

  Future<Either<Failure, CabinetCorrespondent>> create({
    required String displayName,
    String? specialty,
    String? email,
    String? phone,
    String? address,
    String? rpps,
    String? notes,
  });

  Future<Either<Failure, CabinetCorrespondent>> update(
    String id, {
    String? displayName,
    String? specialty,
    String? email,
    String? phone,
    String? address,
    String? rpps,
    String? notes,
  });

  Future<Either<Failure, void>> delete(String id);

  Future<Either<Failure, CorrespondentStats>> getStats(String id);
}
