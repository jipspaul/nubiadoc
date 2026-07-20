import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_patient.dart';

abstract class CabinetPatientsRepository {
  Future<Either<Failure, List<CabinetPatient>>> list({int page = 1});
  Future<Either<Failure, CabinetPatient>> getById(String id);

  /// Création rapide d'un dossier patient (sans compte plateforme requis) —
  /// `POST /v1/cabinet/patients/quick` (#4038). Distinct de l'ancien
  /// rattachement par `patient_account_id` (hors scope ici) : pas de
  /// `CabinetPatient` complet en entrée, ses champs serveur (id, cabinetId,
  /// createdAt) n'existent pas encore côté client.
  Future<Either<Failure, CabinetPatient>> create({
    required String firstName,
    required String lastName,
    String? phone,
    DateTime? birthDate,
  });

  Future<Either<Failure, CabinetPatient>> update(CabinetPatient patient);
  Future<Either<Failure, CabinetPatient>> updateNotes(String id, String note);
}
