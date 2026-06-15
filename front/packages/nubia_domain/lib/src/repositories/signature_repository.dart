import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';

abstract class SignatureRepository {
  /// Crée ou récupère le lien Yousign pour [documentId].
  /// [idempotencyKey] évite la double-création côté API.
  Future<Either<Failure, Uri>> getSignatureUrl({
    required String documentId,
    required String idempotencyKey,
  });

  /// Confirme la signature auprès du backend (polling / webhook).
  Future<Either<Failure, void>> confirmSigned(String documentId);
}
