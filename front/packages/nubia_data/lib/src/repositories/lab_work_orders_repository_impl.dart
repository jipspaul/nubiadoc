import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/lab_work_orders/lab_work_orders_api.dart';
import 'package:nubia_domain/src/entities/lab_work_order.dart';
import 'package:nubia_domain/src/repositories/lab_work_orders_repository.dart';

class LabWorkOrdersRepositoryImpl implements LabWorkOrdersRepository {
  final LabWorkOrdersApi _api;

  const LabWorkOrdersRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<LabWorkOrder>>> listOrders() async {
    try {
      final dtos = await _api.listOrders();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les bons de travaux.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, String>> updateStatus(
      String orderId, String status) async {
    try {
      final newStatus = await _api.updateStatus(orderId, status);
      return Right(newStatus);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure());
      }
      // 409 invalid_status (#4148) : retour arrière refusé côté API.
      if (e.response?.statusCode == 409) {
        return const Left(ServerFailure(
          message: 'Transition de statut invalide.',
          statusCode: 409,
        ));
      }
      return Left(ServerFailure(
        message: "Impossible de mettre à jour le statut.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
