import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy.dart';
import 'package:nubia_domain/src/error/failure.dart';

/// Annuaire public des pharmacies (patient + praticien).
abstract class PharmacyDirectoryRepository {
  /// GET /v1/pharmacies — recherche par nom et/ou proximité.
  Future<Either<Failure, List<Pharmacy>>> search({
    String? query,
    double? lat,
    double? lng,
    double? radiusKm,
  });

  /// GET /v1/cabinet/patients/{id}/pharmacy — pharmacie déclarée du patient
  /// (vue praticien). Right(null) si le patient n'en a pas déclaré.
  Future<Either<Failure, Pharmacy?>> getPatientPharmacy(String patientId);
}
