import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/periodontal_chart.dart';

abstract class PeriodontalChartRepository {
  /// Bilan le plus récent (le serveur ne garde pas d'historique consultable
  /// autrement qu'en base — un seul bilan renvoyé, le plus récent).
  Future<Either<Failure, PeriodontalChart>> get(String patientId);

  /// Crée un NOUVEAU bilan (pas un patch/upsert du précédent — chaque PUT
  /// est une capture datée immuable côté API, cf. `periodontal_chart.rs`).
  Future<Either<Failure, PeriodontalChart>> put(
    String patientId,
    Map<String, ToothSiteDepths> sites,
    Map<String, double> indices,
  );
}
