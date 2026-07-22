import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/implant_item.dart';

abstract class ImplantPassportRepository {
  /// GET /v1/implant-passport (#4142), du plus récent au plus ancien.
  Future<Either<Failure, List<ImplantItem>>> listPassport();

  /// GET /v1/implant-passport/export (#4142). Suit la redirection 302 et
  /// renvoie l'URL signée du PDF.
  Future<Either<Failure, String>> exportPassport();
}
