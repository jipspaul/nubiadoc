import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/sterilization_cycle.dart';

abstract class SterilizationRepository {
  /// GET /v1/cabinet/sterilization-cycles (#4138), du plus récent au plus
  /// ancien.
  Future<Either<Failure, List<SterilizationCycle>>> listCycles();

  /// POST /v1/cabinet/sterilization-cycles/:id/pouches (#4138/#4139).
  /// Renvoie l'id de la pochette créée.
  Future<Either<Failure, String>> addPouch(
    String cycleId, {
    required String code,
    String? consultationActId,
  });
}
