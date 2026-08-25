import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/implant_item.dart';

abstract class ImplantPassportRepository {
  /// GET /v1/implant-passport (#4142), du plus récent au plus ancien.
  Future<Either<Failure, List<ImplantItem>>> listPassport();

  /// GET /v1/implant-passport/export (#4142). Suit la redirection 302 et
  /// renvoie l'URL signée du PDF. `implantId` limite l'export à cet implant
  /// seul (#5334) — évite de transmettre tout l'historique pour un partage
  /// ciblé ; absent → export du passeport complet.
  Future<Either<Failure, String>> exportPassport({String? implantId});

  /// POST /v1/cabinet/patients/{id}/implants (#4140/#4141) — écriture côté
  /// praticien. Renvoie l'implant créé (reconstruit à partir des valeurs du
  /// formulaire : la route ne renvoie que l'id).
  Future<Either<Failure, ImplantItem>> createImplant({
    required String patientId,
    required String brand,
    required String implantRef,
    String? lotNumber,
    String? placementDate,
    String? toothPosition,
    String? notes,
  });
}
