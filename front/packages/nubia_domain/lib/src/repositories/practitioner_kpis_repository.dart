import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/practitioner_kpis.dart';

abstract class PractitionerKpisRepository {
  /// GET /v1/me/kpis?period=YYYY-MM (#7189). [period] au format `YYYY-MM`,
  /// `null` = mois courant côté API.
  Future<Either<Failure, PractitionerKpis>> getMyKpis({String? period});
}
