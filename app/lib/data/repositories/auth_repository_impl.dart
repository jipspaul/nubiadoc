import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/core/storage/token_storage.dart';
import 'package:nubia_patient/data/remote/auth/auth_api.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';
import 'package:nubia_patient/domain/repositories/auth_repository.dart';

@LazySingleton(as: AuthRepository)
class AuthRepositoryImpl implements AuthRepository {
  final AuthApi _api;
  final TokenStorage _tokenStorage;

  const AuthRepositoryImpl(this._api, this._tokenStorage);

  @override
  Future<Either<Failure, PatientAccount>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _api.login(email: email, password: password);
      await _tokenStorage.saveTokens(
        access: response.tokens.accessToken,
        refresh: response.tokens.refreshToken,
      );
      return Right(response.account.toDomain());
    } on DioException catch (e) {
      return Left(_mapDioError(e));
    }
  }

  @override
  Future<Either<Failure, PatientAccount>> register({
    required String email,
    required String password,
    required String inviteToken,
  }) async {
    try {
      final response = await _api.register(
        email: email,
        password: password,
        inviteToken: inviteToken,
      );
      await _tokenStorage.saveTokens(
        access: response.tokens.accessToken,
        refresh: response.tokens.refreshToken,
      );
      return Right(response.account.toDomain());
    } on DioException catch (e) {
      return Left(_mapDioError(e));
    }
  }

  @override
  Future<Either<Failure, PatientAccount>> getMe() async {
    try {
      final dto = await _api.getMe();
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(_mapDioError(e));
    }
  }

  @override
  Future<Either<Failure, void>> logout() async {
    await _tokenStorage.clearTokens();
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> refreshToken() async {
    try {
      final currentRefresh = await _tokenStorage.getRefreshToken();
      if (currentRefresh == null) {
        return const Left(UnauthorizedFailure());
      }
      final tokens = await _api.refresh(refreshToken: currentRefresh);
      await _tokenStorage.saveTokens(
        access: tokens.accessToken,
        refresh: tokens.refreshToken,
      );
      return const Right(null);
    } on DioException catch (e) {
      return Left(_mapDioError(e));
    }
  }

  @override
  Future<bool> isAuthenticated() async {
    final token = await _tokenStorage.getAccessToken();
    return token != null;
  }

  Failure _mapDioError(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 401) return const UnauthorizedFailure();
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return const NetworkFailure();
    }
    return ServerFailure(
      message: 'Erreur serveur lors de l\'authentification.',
      statusCode: statusCode,
    );
  }
}
