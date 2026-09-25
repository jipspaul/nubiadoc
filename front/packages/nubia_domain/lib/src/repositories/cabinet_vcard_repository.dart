import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';

abstract class CabinetVcardRepository {
  /// GET /v1/cabinet/vcard (#7146) — vCard 4.0 (`.vcf`) du cabinet courant,
  /// octets bruts pour partage/téléchargement.
  Future<Either<Failure, List<int>>> fetchVcard();

  /// GET /v1/cabinet/vcard/qr.png (#7146) — QR (PNG) encodant la même vCard.
  Future<Either<Failure, List<int>>> fetchVcardQrPng();
}
