import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy_order.dart';
import 'package:nubia_domain/src/error/failure.dart';

/// Commandes click-and-collect, vue pharmacie (JWT kind="pharma").
abstract class PharmacyOrdersRepository {
  /// GET /v1/pharmacy/orders?status=
  Future<Either<Failure, List<PharmacyOrder>>> list({
    PharmacyOrderStatus? status,
  });

  /// GET /v1/pharmacy/orders/{id}
  Future<Either<Failure, PharmacyOrder>> getById(String id);

  /// POST /v1/pharmacy/orders/{id}/accept — received → preparing.
  Future<Either<Failure, PharmacyOrder>> accept(String id);

  /// POST /v1/pharmacy/orders/{id}/ready — preparing → ready.
  Future<Either<Failure, PharmacyOrder>> markReady(String id);

  /// POST /v1/pharmacy/orders/{id}/reject — received → rejected, motif requis.
  Future<Either<Failure, PharmacyOrder>> reject(String id, String reason);

  /// POST /v1/pharmacy/orders/pickup-scan — ready → pickedUp.
  /// [token] = contenu du QR patient (opaque, zéro PII).
  Future<Either<Failure, PharmacyOrder>> confirmPickup(String token);

  /// GET /v1/pharmacy/orders/{id}/document — URL signée du PDF d'ordonnance.
  Future<Either<Failure, String>> getPrescriptionUrl(String id);
}
