import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/stock_import_result.dart';

abstract class StockImportRepository {
  /// POST /v1/stock/import (#7183) : import de lignes de facture fournisseur
  /// saisies en CSV `ref;libellé;quantité;prix` (`prix` optionnel).
  Future<Either<Failure, StockImportResult>> importCsv(String csv);
}
