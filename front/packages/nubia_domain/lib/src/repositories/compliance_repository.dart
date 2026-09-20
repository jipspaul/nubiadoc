import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/compliance_item.dart';
import 'package:nubia_domain/src/entities/custom_device_declaration_result.dart';
import 'package:nubia_domain/src/error/failure.dart';

abstract class ComplianceRepository {
  /// GET /v1/cabinet/compliance-items (#7170) — échéance croissante, chaque
  /// item porte `alertLevel` calculé côté back.
  Future<Either<Failure, List<ComplianceItem>>> listItems();

  /// POST /v1/cabinet/compliance-items (#7170). Renvoie l'id créé.
  Future<Either<Failure, String>> createItem({
    required String kind,
    required String label,
    String? subjectUserId,
    String? equipmentLabel,
    required String dueDate,
    int? recurrenceMonths,
  });

  /// POST /v1/cabinet/compliance-items/:id/complete (#7170) — clôture
  /// l'item ; s'il porte une récurrence, le back recrée automatiquement
  /// l'item suivant (ignoré ici, la liste est rechargée après coup).
  Future<Either<Failure, String>> completeItem(String itemId);

  /// PATCH /v1/cabinet/compliance-items/:id (#7170) — rattache le
  /// justificatif déjà présent au coffre-fort documentaire.
  Future<Either<Failure, ComplianceItem>> attachEvidence({
    required String itemId,
    required String evidenceDocumentId,
  });

  /// POST /v1/patients/:id/custom-device-declarations (#7170) — déclare un
  /// dispositif médical sur mesure (DMSM) depuis la fiche patient.
  Future<Either<Failure, CustomDeviceDeclarationResult>> declareCustomDevice({
    required String patientId,
    required String labName,
    required String deviceDescription,
    String? consultationActId,
  });
}
