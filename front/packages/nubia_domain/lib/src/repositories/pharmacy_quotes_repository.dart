import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy_quote.dart';
import 'package:nubia_domain/src/error/failure.dart';

/// Devis d'officine — vue pharmacie (/v1/pharmacy/quotes*)
/// et vue patient (/v1/account/pharmacy-quotes*).
abstract class PharmacyQuotesRepository {
  /// Liste des devis de l'espace courant (pharmacie ou patient).
  Future<Either<Failure, List<PharmacyQuote>>> list();

  /// POST /v1/pharmacy/quotes
  Future<Either<Failure, PharmacyQuote>> create({
    required String patientAccountId,
    required List<PharmacyQuoteItem> items,
    String? orderId,
  });

  /// POST /v1/pharmacy/quotes/{id}/send — draft → sent.
  Future<Either<Failure, PharmacyQuote>> send(String id);

  /// POST /v1/pharmacy/quotes/{id}/remind — relance d'un devis `sent`.
  Future<Either<Failure, PharmacyQuote>> remind(String id);

  /// POST /v1/account/pharmacy-quotes/{id}/accept|refuse (patient).
  Future<Either<Failure, PharmacyQuote>> decide(String id,
      {required bool accept});
}
