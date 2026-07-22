import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/stock_items/stock_items_api.dart';
import 'package:nubia_domain/src/entities/stock_item.dart';
import 'package:nubia_domain/src/repositories/stock_items_repository.dart';

class StockItemsRepositoryImpl implements StockItemsRepository {
  final StockItemsApi _api;

  const StockItemsRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<StockItem>>> listItems() async {
    try {
      final dtos = await _api.listItems();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de charger l'inventaire.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, int>> addMovement(
    String itemId, {
    required int delta,
    required String reason,
    String? expiryDate,
    String? consultationActId,
  }) async {
    try {
      final quantityOnHand = await _api.addMovement(
        itemId,
        delta: delta,
        reason: reason,
        expiryDate: expiryDate,
        consultationActId: consultationActId,
      );
      return Right(quantityOnHand);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure());
      }
      return Left(ServerFailure(
        message: "Impossible d'enregistrer le mouvement de stock.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
