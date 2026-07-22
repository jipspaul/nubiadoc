import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/stock_item.dart';

abstract class StockItemsRepository {
  /// GET /v1/cabinet/stock-items (#4146), par référence.
  Future<Either<Failure, List<StockItem>>> listItems();

  /// POST /v1/cabinet/stock-items/:id/movements (#4146). Renvoie la
  /// nouvelle `quantity_on_hand`.
  Future<Either<Failure, int>> addMovement(
    String itemId, {
    required int delta,
    required String reason,
    String? expiryDate,
    String? consultationActId,
  });
}
