import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/consultation_cr.dart';

abstract class ConsultationCrRepository {
  /// GET /v1/cabinet/consultations/:id/cr (#7154).
  Future<Either<Failure, ConsultationCr>> getConsultationCr(
    String consultationId,
  );

  /// PUT /v1/cabinet/consultations/:id/cr (#7154) — sauvegarde du brouillon,
  /// appelée à chaque autosave, idempotente.
  Future<Either<Failure, ConsultationCr>> saveConsultationCr({
    required String consultationId,
    String? templateId,
    required List<CrSectionEntry> sections,
  });

  /// POST /v1/cabinet/consultations/:id/cr/finalize (#7154).
  Future<Either<Failure, ConsultationCr>> finalizeConsultationCr(
    String consultationId,
  );
}
