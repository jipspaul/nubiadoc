import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_brief.dart';

abstract class CabinetBriefsRepository {
  /// GET /v1/cabinet/briefs/{view} (#7191/#7192). `view` : "day" | "week" |
  /// "prostheses". `date` (`YYYY-MM-DD`, défaut aujourd'hui) borne la fenêtre.
  Future<Either<Failure, CabinetBrief>> fetch({
    required String view,
    String? date,
  });

  /// GET /v1/cabinet/briefs/{view}.pdf (#7191/#7192) — mêmes paramètres que
  /// [fetch], renvoie les octets bruts du PDF pour impression/partage.
  Future<Either<Failure, List<int>>> fetchPdf({
    required String view,
    String? date,
  });
}
