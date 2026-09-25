import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/cabinet_vcard/cabinet_vcard_api.dart';
import 'package:nubia_domain/src/repositories/cabinet_vcard_repository.dart';

class CabinetVcardRepositoryImpl implements CabinetVcardRepository {
  final CabinetVcardApi _api;

  const CabinetVcardRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<int>>> fetchVcard() async {
    try {
      final bytes = await _api.fetchVcard();
      return Right(bytes);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401) return const Left(UnauthorizedFailure());
      if (status == 404) return const Left(NotFoundFailure());
      return Left(ServerFailure(
        message: 'Impossible de charger la carte de visite du cabinet.',
        statusCode: status,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, List<int>>> fetchVcardQrPng() async {
    try {
      final bytes = await _api.fetchVcardQrPng();
      return Right(bytes);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401) return const Left(UnauthorizedFailure());
      if (status == 404) return const Left(NotFoundFailure());
      return Left(ServerFailure(
        message: 'Impossible de générer le QR de la carte de visite.',
        statusCode: status,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
