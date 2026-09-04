import 'package:dartz/dartz.dart';
import 'package:nubia_data/src/remote/patient_pharmacy/patient_pharmacy_api.dart';
import 'package:nubia_data/src/repositories/pharmacy_failure_mapper.dart';
import 'package:nubia_domain/src/entities/patient_prescription.dart';
import 'package:nubia_domain/src/entities/pharmacy.dart';
import 'package:nubia_domain/src/entities/pharmacy_order.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/patient_pharmacy_repository.dart';

class PatientPharmacyRepositoryImpl implements PatientPharmacyRepository {
  final PatientPharmacyApi _api;

  const PatientPharmacyRepositoryImpl(this._api);

  @override
  Future<Either<Failure, Pharmacy?>> getMyPharmacy() => guardPharmacyCall(
        () async => (await _api.getMyPharmacy())?.toDomain(),
        errorMessage: 'Impossible de charger votre pharmacie.',
      );

  @override
  Future<Either<Failure, Pharmacy>> setMyPharmacy(String pharmacyId) =>
      guardPharmacyCall(
        () async => (await _api.setMyPharmacy(pharmacyId)).toDomain(),
        errorMessage: 'Impossible de déclarer cette pharmacie.',
      );

  @override
  Future<Either<Failure, PharmacyOrder>> createOrder({
    required String prescriptionId,
    required String pharmacyId,
  }) =>
      guardPharmacyCall(
        () async => (await _api.createOrder(
          prescriptionId: prescriptionId,
          pharmacyId: pharmacyId,
        ))
            .toDomain(),
        errorMessage: 'Impossible d’envoyer l’ordonnance à la pharmacie.',
      );

  @override
  Future<Either<Failure, List<PharmacyOrder>>> listOrders() =>
      guardPharmacyCall(
        () async =>
            (await _api.listOrders()).map((dto) => dto.toDomain()).toList(),
        errorMessage: 'Impossible de charger vos commandes.',
      );

  @override
  Future<Either<Failure, PharmacyOrder>> getOrder(String id) =>
      guardPharmacyCall(
        () async => (await _api.getOrder(id)).toDomain(),
        errorMessage: 'Impossible de charger la commande.',
      );

  @override
  Future<Either<Failure, PharmacyOrder>> cancelOrder(String id) =>
      guardPharmacyCall(
        () async => (await _api.cancelOrder(id)).toDomain(),
        errorMessage: 'Impossible d’annuler la commande.',
      );

  @override
  Future<Either<Failure, ({String token, String shortCode})>> getPickupToken(
          String id) =>
      guardPharmacyCall(
        () => _api.getPickupToken(id),
        errorMessage: 'Impossible de générer le code de retrait.',
      );

  @override
  Future<Either<Failure, List<PatientPrescription>>> listPrescriptions() =>
      guardPharmacyCall(
        () async => (await _api.listPrescriptions())
            .map((dto) => dto.toDomain())
            .toList(),
        errorMessage: 'Impossible de charger vos ordonnances.',
      );
}
