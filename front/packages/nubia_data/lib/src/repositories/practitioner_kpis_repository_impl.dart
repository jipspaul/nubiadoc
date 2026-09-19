import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_data/src/remote/practitioner_kpis/practitioner_kpis_api.dart';

class PractitionerKpisRepositoryImpl implements PractitionerKpisRepository {
  final PractitionerKpisApi _api;

  const PractitionerKpisRepositoryImpl(this._api);

  @override
  Future<Either<Failure, PractitionerKpis>> getMyKpis({String? period}) async {
    try {
      final dto = await _api.getMyKpis(period: period);
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
        message: 'Erreur serveur lors du chargement des KPI.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
