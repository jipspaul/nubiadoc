import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/orthodontic_treatment.dart';

abstract class OrthodonticsRepository {
  /// GET /v1/cabinet/patients/:id/orthodontics (#4135).
  Future<Either<Failure, List<OrthodonticTreatment>>> list(String patientId);

  /// POST /v1/cabinet/orthodontics/:id/steps (#4135). Renvoie l'id de
  /// l'étape créée.
  Future<Either<Failure, String>> addStep(
    String treatmentId, {
    required int stepNumber,
    required String kind,
    String? conformityNotes,
  });
}
