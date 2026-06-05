import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/data/remote/dashboard/dashboard_api.dart';
import 'package:nubia_patient/domain/repositories/dashboard_repository.dart';

@LazySingleton(as: DashboardRepository)
class DashboardRepositoryImpl implements DashboardRepository {
  final DashboardApi _api;

  const DashboardRepositoryImpl(this._api);

  @override
  Future<Either<Failure, DashboardSummary>> getSummary() async {
    try {
      final dto = await _api.getSummary();
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return const Left(NetworkFailure());
      }
      return Left(ServerFailure(
        message: 'Erreur serveur lors du chargement du tableau de bord.',
        statusCode: e.response?.statusCode,
      ));
    }
  }
}
