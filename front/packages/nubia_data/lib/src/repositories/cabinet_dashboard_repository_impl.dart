import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_data/src/remote/cabinet_dashboard/cabinet_dashboard_api.dart';

class CabinetDashboardRepositoryImpl implements CabinetDashboardRepository {
  final CabinetDashboardApi _api;

  const CabinetDashboardRepositoryImpl(this._api);

  @override
  Future<Either<Failure, ProDashboardSummary>> getSummary() async {
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
    } catch (e) {
      return const Left(ParseFailure());
  }
}
