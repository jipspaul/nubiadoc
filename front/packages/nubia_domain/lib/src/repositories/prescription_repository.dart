import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/prescription.dart';
import 'package:nubia_domain/src/entities/prescription_template.dart';

abstract class PrescriptionRepository {
  /// POST /v1/cabinet/prescriptions
  Future<Either<Failure, Prescription>> createPrescription({
    required String patientId,
    required List<PrescriptionItem> items,
  });

  /// POST /v1/cabinet/prescriptions/{id}/sign
  Future<Either<Failure, Prescription>> signPrescription(String id);

  /// POST /v1/cabinet/prescriptions/{id}/send — envoie l'ordonnance signée
  /// à une pharmacie (crée la commande click-and-collect côté pharmacie).
  Future<Either<Failure, Prescription>> sendToPharmacy({
    required String prescriptionId,
    required String pharmacyId,
  });

  /// GET /v1/cabinet/prescription-templates (#4074).
  Future<Either<Failure, List<PrescriptionTemplate>>>
      listPrescriptionTemplates();

  /// POST /v1/cabinet/prescriptions/{id}/apply-template (#4074) — préremplit
  /// un brouillon, renvoie l'ordonnance mise à jour (re-fetch : la route
  /// d'application ne renvoie que le nombre de lignes créées).
  Future<Either<Failure, Prescription>> applyPrescriptionTemplate({
    required String prescriptionId,
    required String templateId,
  });

  /// GET /v1/cabinet/patients/{id}/prescriptions (#4132) — historique des
  /// ordonnances du patient (vue cabinet), brouillons inclus.
  Future<Either<Failure, List<Prescription>>> listPrescriptions(
    String patientId,
  );

  /// POST /v1/cabinet/prescriptions/{id}/renew (#4132) — duplique
  /// l'ordonnance en un nouveau brouillon, renvoie l'ordonnance créée
  /// (re-fetch : la route renew ne renvoie que l'id).
  Future<Either<Failure, Prescription>> renewPrescription(
    String prescriptionId,
  );
}
