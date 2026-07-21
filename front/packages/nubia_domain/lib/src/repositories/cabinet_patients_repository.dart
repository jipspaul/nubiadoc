import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_patient.dart';

abstract class CabinetPatientsRepository {
  /// `q` : recherche serveur (`GET /v1/cabinet/patients?q=`, #4043) — filtre
  /// `ILIKE` nom/prénom côté API (`list_cabinet_patients`, `clinical.rs`).
  /// Remplace le filtrage en mémoire (ne scale plus au-delà de quelques
  /// centaines de dossiers). Téléphone/n° dossier : hors scope ici, la
  /// requête SQL de `q` ne les couvre pas encore côté API.
  Future<Either<Failure, List<CabinetPatient>>> list({
    int page = 1,
    String? q,
  });
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
