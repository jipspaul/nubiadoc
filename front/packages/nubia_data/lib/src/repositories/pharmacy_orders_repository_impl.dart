import 'package:dartz/dartz.dart';
import 'package:nubia_data/src/remote/pharmacy_orders/pharmacy_orders_api.dart';
import 'package:nubia_data/src/repositories/pharmacy_failure_mapper.dart';
import 'package:nubia_domain/src/entities/pharmacy_order.dart';
import 'package:nubia_domain/src/entities/prescription.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_orders_repository.dart';

class PharmacyOrdersRepositoryImpl implements PharmacyOrdersRepository {
  final PharmacyOrdersApi _api;

  const PharmacyOrdersRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<PharmacyOrder>>> list({
    PharmacyOrderStatus? status,
  }) =>
      guardPharmacyCall(
        () async {
          final dtos = await _api.list(status: status);
          return dtos.map((dto) => dto.toDomain()).toList();
        },
        errorMessage: 'Impossible de charger les commandes.',
      );

  @override
  Future<Either<Failure, PharmacyOrder>> getById(String id) =>
      guardPharmacyCall(
        () async => (await _api.getById(id)).toDomain(),
        errorMessage: 'Impossible de charger la commande.',
      );

  @override
  Future<Either<Failure, PharmacyOrder>> accept(String id) => guardPharmacyCall(
        () async => (await _api.accept(id)).toDomain(),
        errorMessage: 'Impossible de démarrer la préparation.',
      );

  @override
  Future<Either<Failure, PharmacyOrder>> markReady(String id) =>
      guardPharmacyCall(
        () async => (await _api.markReady(id)).toDomain(),
        errorMessage: 'Impossible de marquer la commande prête.',
      );

  @override
  Future<Either<Failure, PharmacyOrder>> reject(String id, String reason) =>
      guardPharmacyCall(
        () async => (await _api.reject(id, reason)).toDomain(),
        errorMessage: 'Impossible de refuser la commande.',
      );

  @override
  Future<Either<Failure, PharmacyOrder>> confirmPickup(
    String token, {
    required String expectedOrderId,
  }) =>
      guardPharmacyCall(
        () async => (await _api.pickupScan(
          token,
          expectedOrderId: expectedOrderId,
        ))
            .toDomain(),
        errorMessage: 'Impossible de valider le retrait.',
      );

  @override
  Future<Either<Failure, String>> getPrescriptionUrl(String id) =>
      guardPharmacyCall(
        () => _api.getDocumentUrl(id),
        errorMessage: 'Impossible d’ouvrir l’ordonnance.',
      );

  @override
  Future<Either<Failure, List<PrescriptionItem>>> getPrescriptionItems(
    String id,
  ) =>
      guardPharmacyCall(
        () async {
          final dtos = await _api.getItems(id);
          return dtos.map((dto) => dto.toDomain()).toList();
        },
        errorMessage: 'Impossible de charger les lignes de l’ordonnance.',
      );
}
