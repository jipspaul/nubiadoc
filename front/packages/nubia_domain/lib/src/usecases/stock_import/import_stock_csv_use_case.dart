import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/stock_import_result.dart';
import 'package:nubia_domain/src/repositories/stock_import_repository.dart';

class ImportStockCsvUseCase {
  final StockImportRepository _repository;

  const ImportStockCsvUseCase(this._repository);

  Future<Either<Failure, StockImportResult>> call(String csv) =>
      _repository.importCsv(csv);
}
