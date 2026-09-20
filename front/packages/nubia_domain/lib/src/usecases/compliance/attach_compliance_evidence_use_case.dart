import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/compliance_item.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/compliance_repository.dart';

/// Rattache un justificatif (attestation, rapport de contrôle) déjà présent
/// au coffre-fort documentaire à un item de l'échéancier (#7170) —
/// `PATCH /v1/cabinet/compliance-items/:id`.
class AttachComplianceEvidenceUseCase {
  final ComplianceRepository _repository;

  const AttachComplianceEvidenceUseCase(this._repository);

  Future<Either<Failure, ComplianceItem>> call({
    required String itemId,
    required String evidenceDocumentId,
  }) =>
      _repository.attachEvidence(
        itemId: itemId,
        evidenceDocumentId: evidenceDocumentId,
      );
}
