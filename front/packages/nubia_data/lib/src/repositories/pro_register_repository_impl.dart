import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_core/src/storage/token_storage.dart';
import 'package:nubia_data/src/remote/auth/pro_register_api.dart';
import 'package:nubia_domain/src/entities/pro_session.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pro_register_repository.dart';

class ProRegisterRepositoryImpl implements ProRegisterRepository {
  final ProRegisterApi _api;
  final TokenStorage _tokenStorage;

  const ProRegisterRepositoryImpl(this._api, this._tokenStorage);

  @override
  Future<Either<Failure, ProSession>> register(
      ProRegisterRequest request) async {
    try {
      final dto = await _api.register(request);
      // POST /v1/pro/register ne retourne pas de refresh_token (onboarding uniquement).
      // Le flux D2 appellera AuthCubit.restore() pour établir la session complète.
      await _tokenStorage.saveTokens(
        access: dto.accessToken,
        refresh: '',
      );
      return Right(
        ProSession(
          userId: dto.accountId,
          cabinetId: dto.cabinetId,
          providerId: dto.providerId,
        ),
      );
    } on DioException catch (e) {
      return Left(_mapDioError(e));
    } catch (_) {
      return const Left(ParseFailure());
    }
  }

  Failure _mapDioError(DioException e) {
    final statusCode = e.response?.statusCode;
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return const NetworkFailure();
    }
    return ServerFailure(
      message: 'Erreur lors de la création du compte praticien.',
      statusCode: statusCode,
    );
  }
}
