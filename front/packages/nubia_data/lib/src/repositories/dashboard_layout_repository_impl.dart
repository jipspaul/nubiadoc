import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_data/src/remote/dashboard_layout/dashboard_layout_api.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/dashboard_layout_repository.dart';

class DashboardLayoutRepositoryImpl implements DashboardLayoutRepository {
  final DashboardLayoutApi _api;

  const DashboardLayoutRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<String>>> getLayout() async {
    try {
      return Right(await _api.getLayout());
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors du chargement du tableau de bord.'));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, List<String>>> updateLayout(
    List<String> widgetIds,
  ) async {
    try {
      return Right(await _api.updateLayout(widgetIds));
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors de la mise à jour du tableau de bord.'));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  Failure _mapDioError(DioException e, String defaultMessage) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return const OfflineFailure();
    }
    if (e.response?.statusCode == 401) {
      return const UnauthorizedFailure();
    }
    return ServerFailure(
      message: defaultMessage,
      statusCode: e.response?.statusCode,
    );
  }
}
