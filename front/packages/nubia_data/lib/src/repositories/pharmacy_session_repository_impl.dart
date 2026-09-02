import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_core/src/storage/token_storage.dart';
import 'package:nubia_data/src/remote/pharmacy_session/pharmacy_session_api.dart';
import 'package:nubia_data/src/repositories/pharmacy_failure_mapper.dart';
import 'package:nubia_domain/src/entities/pharmacy_session.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_session_repository.dart';

class PharmacySessionRepositoryImpl implements PharmacySessionRepository {
  final PharmacySessionApi _api;
  final TokenStorage _tokenStorage;

  PharmacySessionRepositoryImpl(this._api, this._tokenStorage);

  /// Dernier contexte sélectionné — permet de re-scoper le token après un
  /// refresh (le refresh renvoie un token de login `kind:"pro"`, qui serait
  /// rejeté en 403 par /v1/pharmacy/*). Voir [reselectContext].
  String? _selectedPharmacyId;

  @override
  Future<Either<Failure, ({String? displayName, List<PharmacyMembership> memberships})>>
      myMemberships() => guardPharmacyCall(
            () async {
              final result = await _api.myMemberships();
              return (
                displayName: result.displayName,
                memberships:
                    result.memberships.map((dto) => dto.toDomain()).toList(),
              );
            },
            errorMessage: 'Impossible de charger vos accès pharmacie.',
          );

  @override
  Future<Either<Failure, PharmacyContext>> selectContext(
    String pharmacyId,
  ) async {
    try {
      final dto = await _api.selectContext(pharmacyId);
      if (dto.accessToken.isEmpty) {
        return const Left(ParseFailure());
      }
      // Le refresh token du login commun reste valable : seule la partie
      // access est remplacée par le JWT scopé kind:"pharma".
      final refresh = await _tokenStorage.getRefreshToken();
      await _tokenStorage.saveTokens(
        access: dto.accessToken,
        refresh: refresh ?? '',
      );
      _selectedPharmacyId = pharmacyId;
      return Right(dto.toDomain());
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 403) {
        return const Left(
          ServerFailure(
            message: 'Ce compte n’a pas accès à cette pharmacie.',
            statusCode: 403,
            code: 'no_membership',
          ),
        );
      }
      if (status == 401) return const Left(UnauthorizedFailure());
      if (status == 404) return const Left(NotFoundFailure());
      return Left(
        ServerFailure(
          message: 'Impossible d’ouvrir l’espace pharmacie.',
          statusCode: status,
        ),
      );
    } catch (_) {
      return const Left(ParseFailure());
    }
  }

  /// Re-scope le token courant sur la pharmacie sélectionnée après un refresh.
  ///
  /// Branché sur `AuthInterceptor.onTokensRefreshed` (app pharmacie) : le
  /// refresh a réécrit un token de login `kind:"pro"` dans le storage, on
  /// l'échange contre un JWT `kind:"pharma"` via le [plainDio] fourni (sans
  /// interceptors — pas de réentrance sur le refresh en cours). No-op tant
  /// qu'aucun contexte n'a été sélectionné.
  Future<void> reselectContext(Dio plainDio) async {
    final pharmacyId = _selectedPharmacyId;
    if (pharmacyId == null) return;
    final access = await _tokenStorage.getAccessToken();
    if (access == null || access.isEmpty) return;
    final response = await plainDio.post<Map<String, dynamic>>(
      '/auth/select-pharmacy-context',
      data: {'pharmacy_id': pharmacyId},
      options: Options(headers: {'Authorization': 'Bearer $access'}),
    );
    final token = response.data?['access_token'] as String?;
    if (token == null || token.isEmpty) return;
    final refresh = await _tokenStorage.getRefreshToken();
    await _tokenStorage.saveTokens(access: token, refresh: refresh ?? '');
  }
}
