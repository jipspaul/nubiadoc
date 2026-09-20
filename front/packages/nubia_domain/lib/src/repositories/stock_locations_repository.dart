import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/stock_location.dart';
import 'package:nubia_domain/src/entities/stock_item_location.dart';

abstract class StockLocationsRepository {
  /// GET /v1/cabinet/stock-locations (#7183).
  Future<Either<Failure, List<StockLocation>>> listLocations();

  /// POST /v1/cabinet/stock-locations (#7183). Renvoie l'id créé.
  Future<Either<Failure, String>> createLocation(String name);

  /// GET /v1/cabinet/stock-items/:id/locations (#7183) : quantité et seuil
  /// de cet article dans chaque localisation du cabinet.
  Future<Either<Failure, List<StockItemLocation>>> listItemLocations(
    String itemId,
  );

  /// PATCH /v1/cabinet/stock-items/:id/locations/:locationId (#7183) : fixe
  /// (ou efface, `null`) le seuil d'alerte de cet article pour cette
  /// localisation.
  Future<Either<Failure, void>> setItemLocationThreshold(
    String itemId,
    String locationId, {
    int? threshold,
  });

  /// POST /v1/cabinet/stock-items/:id/transfer (#7183). Renvoie les
  /// nouvelles quantités `(from, to)`.
  Future<Either<Failure, (int fromQuantity, int toQuantity)>> transfer(
    String itemId, {
    required String fromLocationId,
    required String toLocationId,
    required int quantity,
  });
}
