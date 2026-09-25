import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';

/// Port pour `POST /v1/cabinet/provider/signature` et
/// `POST /v1/cabinet/provider/stamp` (#7148) — upload de la signature
/// manuscrite et du tampon du praticien connecté, apposés sur les PDF
/// générés (devis, ordonnances, courriers). JPEG uniquement côté back.
abstract class ProviderStampRepository {
  Future<Either<Failure, String>> uploadSignature({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  });

  Future<Either<Failure, String>> uploadStamp({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  });
}
