import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/sterilization_cycle.dart';
import 'package:nubia_domain/src/entities/sterilized_pouch_use.dart';

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

  /// GET /v1/sterilization/cycles/:id/labels.pdf (#7181/#7180) — octets
  /// bruts de la planche d'étiquettes du cycle, pour impression/partage.
  Future<Either<Failure, List<int>>> fetchLabelsPdf(
    String cycleId, {
    int? shelfLifeDays,
  });

  /// POST /v1/sterilization/pouches/:code/use (#7181/#7180) — rattache le
  /// sachet scanné à [patientId] (et optionnellement à [consultationId]),
  /// idempotent.
  Future<Either<Failure, SterilizedPouchUse>> usePouch(
    String code, {
    required String patientId,
    String? consultationId,
  });
}
