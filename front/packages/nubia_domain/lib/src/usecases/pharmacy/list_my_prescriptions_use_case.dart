import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/patient_prescription.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/patient_pharmacy_repository.dart';

class ListMyPrescriptionsUseCase {
  final PatientPharmacyRepository _repository;

  const ListMyPrescriptionsUseCase(this._repository);

  /// [limit] borne le nombre d'ordonnances à une seule page — omis, suit le
  /// curseur jusqu'à épuisement pour ramener l'historique complet (#7554).
  Future<Either<Failure, List<PatientPrescription>>> call({int? limit}) =>
      _repository.listPrescriptions(limit: limit);
}
