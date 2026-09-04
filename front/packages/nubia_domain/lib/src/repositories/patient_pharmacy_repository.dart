import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/patient_prescription.dart';
import 'package:nubia_domain/src/entities/pharmacy.dart';
import 'package:nubia_domain/src/entities/pharmacy_order.dart';
import 'package:nubia_domain/src/error/failure.dart';

/// Pharmacie déclarée + commandes click-and-collect, vue patient.
abstract class PatientPharmacyRepository {
  /// GET /v1/account/pharmacy — Right(null) si aucune pharmacie déclarée.
  Future<Either<Failure, Pharmacy?>> getMyPharmacy();

  /// PUT /v1/account/pharmacy
  Future<Either<Failure, Pharmacy>> setMyPharmacy(String pharmacyId);

  /// POST /v1/account/prescriptions/{prescriptionId}/order
  Future<Either<Failure, PharmacyOrder>> createOrder({
    required String prescriptionId,
    required String pharmacyId,
  });

  /// GET /v1/account/orders
  Future<Either<Failure, List<PharmacyOrder>>> listOrders();

  /// GET /v1/account/orders/{id}
  Future<Either<Failure, PharmacyOrder>> getOrder(String id);

  /// POST /v1/account/orders/{id}/cancel — depuis received/preparing seulement.
  Future<Either<Failure, PharmacyOrder>> cancelOrder(String id);

  /// GET /v1/account/orders/{id}/pickup-token — token opaque du QR de retrait
  /// + code court dictable au comptoir (#6419). Uniquement si la commande
  /// est prête (ready), régénère à chaque appel.
  Future<Either<Failure, ({String token, String shortCode})>> getPickupToken(
      String id);

  /// GET /v1/account/prescriptions — ordonnances du compte (envoi pharmacie).
  Future<Either<Failure, List<PatientPrescription>>> listPrescriptions();
}
