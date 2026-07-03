import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_core/src/storage/token_storage.dart';
import 'package:nubia_data/src/remote/auth/auth_api.dart';
import 'package:nubia_domain/src/entities/patient_account.dart';
import 'package:nubia_domain/src/repositories/auth_repository.dart';
import 'package:nubia_domain/src/repositories/notification_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthApi _api;
  final TokenStorage _tokenStorage;
  final NotificationRepository _notifications;

  const AuthRepositoryImpl(this._api, this._tokenStorage, this._notifications);

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
      // /auth/login ne renvoie pas d'account : on dérive un compte minimal
      // (non utilisé par le flux de session, qui ne garde que les jetons).
      return Right(
        response.account?.toDomain() ??
            PatientAccount(id: '', firstName: '', lastName: '', email: email),
      );
    } on DioException catch (e) {
      // 401 sur /auth/login = identifiants incorrects (pas une session expirée).
      if (e.response?.statusCode == 401) {
        return const Left(InvalidCredentialsFailure());
      }
      return Left(_mapDioError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, PatientAccount>> register({
    required String email,
    required String password,
    required bool acceptCgu,
    required String cguVersion,
    String? inviteToken,
  }) async {
    try {
      final response = await _api.register(
        email: email,
        password: password,
        acceptCgu: acceptCgu,
        cguVersion: cguVersion,
        inviteToken: inviteToken,
      );
      await _tokenStorage.saveTokens(
        access: response.tokens.accessToken,
        refresh: response.tokens.refreshToken,
      );
      return Right(
        response.account?.toDomain() ??
            PatientAccount(id: '', firstName: '', lastName: '', email: email),
      );
    } on DioException catch (e) {
      // 400 + code=invitation_invalid sur un register avec invitation_token =
      // invitation inconnue ou expirée (voir AppError::InvitationInvalid côté API).
      final statusCode = e.response?.statusCode;
      final apiCode = e.response?.data is Map
          ? (e.response!.data as Map)['code'] as String?
          : null;
      if (inviteToken != null &&
          inviteToken.isNotEmpty &&
          statusCode == 400 &&
          apiCode == 'invitation_invalid') {
        return const Left(InvalidInviteFailure());
      }
      return Left(_mapDioError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, String>> registerPro({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? rpps,
    String? adeli,
    required String raisonSociale,
    String? siret,
    required String specialite,
  }) async {
    try {
      final response = await _api.registerPro(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
        rpps: rpps,
        adeli: adeli,
        raisonSociale: raisonSociale,
        siret: siret,
        specialite: specialite,
      );
      await _tokenStorage.saveTokens(
        access: response.accessToken,
        refresh: response.refreshToken,
      );
      return Right(response.accountId);
    } on DioException catch (e) {
      return Left(_mapDioError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, PatientAccount>> getMe() async {
    try {
      final dto = await _api.getMe();
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(_mapDioError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, void>> logout() async {
    final fcmToken = await _tokenStorage.getFcmToken();
    if (fcmToken != null) {
      // Best-effort: ignore failure so logout always completes.
      await _notifications.unregisterFcmToken(fcmToken);
      await _tokenStorage.clearFcmToken();
    }
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
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<bool> isAuthenticated() async {
    final token = await _tokenStorage.getAccessToken();
    return token != null;
  }

  @override
  Future<Either<Failure, void>> forgotPassword({required String email}) async {
    try {
      await _api.forgotPassword(email: email);
      return const Right(null);
    } on DioException catch (e) {
      return Left(_mapDioError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, void>> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    try {
      await _api.resetPassword(token: token, newPassword: newPassword);
      return const Right(null);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 404 || statusCode == 410) {
        return const Left(
          ValidationFailure(message: 'Ce lien de réinitialisation est invalide ou a expiré.'),
        );
      }
      if (statusCode == 422) {
        return const Left(
          ValidationFailure(
            message:
                'Le mot de passe doit contenir au moins 8 caractères dont 1 chiffre.',
          ),
        );
      }
      return Left(_mapDioError(e));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  Failure _mapDioError(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 401) return const UnauthorizedFailure();
    // /auth/login est rate-limité (5/min par IP, 10/5min par email) : sans ce
    // cas, l'utilisateur voyait « Erreur serveur lors de l'authentification »
    // pour un simple excès de tentatives — anxiogène et faux.
    if (statusCode == 429) {
      return const ValidationFailure(
        message:
            'Trop de tentatives de connexion. Patientez une minute puis réessayez.',
      );
    }
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
