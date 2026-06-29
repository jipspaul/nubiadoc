import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_data/src/remote/cabinet_info/cabinet_info_api.dart';

class CabinetRepositoryImpl implements CabinetRepository {
  final CabinetInfoApi _api;

  const CabinetRepositoryImpl(this._api);

  @override
  Future<Either<Failure, void>> updateCabinet(
    UpdateCabinetRequest request,
  ) async {
    try {
      await _api.updateCabinet(
        name: request.name,
        address: request.address,
        phone: request.phone,
        siret: request.siret,
      );
      return const Right(null);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 403) {
        return const Left(
          ServerFailure(
            message: 'Accès refusé. Rôle administrateur requis.',
            statusCode: 403,
          ),
        );
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return const Left(NetworkFailure());
      }
      return Left(ServerFailure(
        message: 'Erreur lors de la mise à jour du cabinet.',
        statusCode: e.response?.statusCode,
      ));
    } catch (_) {
      return const Left(ParseFailure());
    }
  }
}
