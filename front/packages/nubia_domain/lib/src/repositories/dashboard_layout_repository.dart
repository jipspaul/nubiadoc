import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';

/// Persistance de la mise en page personnalisée du dashboard (#7161) —
/// `GET/PUT /v1/me/dashboard-layout`. La liste de widgets est ORDONNÉE et ne
/// contient que les widgets VISIBLES : masquer un widget revient à le retirer
/// de la liste, le réordonner revient à permuter sa position.
abstract class DashboardLayoutRepository {
  Future<Either<Failure, List<String>>> getLayout();

  Future<Either<Failure, List<String>>> updateLayout(List<String> widgetIds);
}
