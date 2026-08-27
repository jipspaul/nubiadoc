import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/medication_reference.dart';
import 'package:nubia_domain/src/error/failure.dart';

abstract class MedicationReferenceRepository {
  /// Recherche des produits dans le référentiel médicament (DCI, forme
  /// galénique, classe thérapeutique) pour la composition d'ordonnance.
  Future<Either<Failure, List<MedicationReference>>> searchMedicationReferences({
    required String query,
  });
}
