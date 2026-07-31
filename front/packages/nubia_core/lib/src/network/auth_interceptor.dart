import 'dart:async';

import 'package:dio/dio.dart';
import 'package:nubia_core/src/storage/token_storage.dart';

/// Injects Bearer JWT into every request.
/// Handles 401 → token refresh → retry (once).
/// On refresh failure → clears tokens (caller should redirect to login).
class AuthInterceptor extends Interceptor {
  final TokenStorage _tokenStorage;
  // Sentinel path used internally for refresh calls — must not be intercepted.
  static const _refreshPath = '/auth/refresh';
  // When non-null, a refresh is in progress. Concurrent 401s await this
  // completer and each retries its own request once it resolves.
  Completer<void>? _refreshCompleter;
  // Shared adapter injected by ApiClient so tests can swap it.
  HttpClientAdapter? _httpClientAdapter;

  /// Hook post-refresh optionnel. Le refresh renvoie toujours un token de
  /// login « de base » : une app dont la session vit dans un contexte dérivé
  /// (ex. app pharmacie, JWT `kind:"pharma"` obtenu via
  /// `POST /v1/auth/select-pharmacy-context`) enregistre ici la re-sélection
  /// du contexte, qui doit relire/écrire le [TokenStorage].
  ///
  /// Le hook reçoit un [Dio] **sans interceptors** (même adapter que le
  /// refresh) : il ne repasse pas par cet interceptor, donc aucun risque de
  /// réentrance sur le refresh en cours. Best-effort : une erreur du hook
  /// n'annule pas le refresh, et la requête est rejouée avec le token présent
  /// en storage après le hook.
  Future<void> Function(Dio plainDio)? onTokensRefreshed;

  AuthInterceptor(this._tokenStorage);

  /// Called by [ApiClient] after constructing [Dio], so tests can inject
  /// a fake [HttpClientAdapter] via the shared [Dio] instance.
  void setDio(Dio dio) => _httpClientAdapter = dio.httpClientAdapter;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    String? token;
    try {
      token = await _tokenStorage.getAccessToken();
    } catch (_) {
      // A storage read racing with a just-completed login/refresh write
      // must not abort the request before it ever reaches the network —
      // that would surface as a client-side DioException with zero
      // network trace. Let it go out unauthenticated so a real 401
      // (visible, and handled by the refresh flow below) is raised instead.
      token = null;
    }
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final path = err.requestOptions.path;

    // Only handle 401 on non-refresh endpoints (avoid infinite loop).
    if (response?.statusCode != 401 || path == _refreshPath) {
      handler.next(err);
      return;
    }

    if (_refreshCompleter != null) {
      // A refresh is already in progress — wait for it, then retry this request.
      try {
        await _refreshCompleter!.future;
        final newAccess = await _tokenStorage.getAccessToken();
        final retryOptions = err.requestOptions
          ..headers['Authorization'] = 'Bearer $newAccess';
        final retryDio = _buildPlainDio(retryOptions.baseUrl);
        final retryResponse = await retryDio.fetch<dynamic>(retryOptions);
        handler.resolve(retryResponse);
      } on DioException catch (_) {
        handler.next(err);
      } catch (_) {
        handler.next(err);
      }
      return;
    }

    _refreshCompleter = Completer<void>();
    // Suppress unhandled-error if no concurrent request is awaiting the future.
    _refreshCompleter!.future.ignore();
    try {
      String? refreshToken;
      var storageReadFailed = false;
      // #4533 : un `null`/une exception isolés peuvent être un vrai read
      // transitoire (storage pas encore prêt, ex. IndexedDB sur web tout
      // juste après un boot/reload) plutôt qu'une vraie absence de token —
      // observé en prod : 401 → AUCUN appel /auth/refresh tenté →
      // déconnexion, alors que le refresh token était valide en storage
      // l'instant d'après. On retente quelques fois avant de conclure à une
      // absence réelle (et déconnecter l'utilisateur).
      for (var attempt = 0; attempt < 3; attempt++) {
        storageReadFailed = false;
        try {
          refreshToken = await _tokenStorage.getRefreshToken();
        } catch (_) {
          // Même classe de race que le read de onRequest ci-dessus : un
          // read en cours d'écriture (ex. juste après un login/refresh) ne
          // doit jamais s'échapper en exception non catchée — Dio la
          // transformerait en DioException côté client sans jamais
          // atteindre l'endpoint de refresh. Traité comme transitoire, pas
          // comme "déconnecté", pour ne pas effacer des tokens valides sur
          // une simple race.
          storageReadFailed = true;
        }
        if (refreshToken != null) break;
        if (attempt < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
      if (refreshToken == null) {
        if (!storageReadFailed) {
          await _tokenStorage.clearTokens();
        }
        _refreshCompleter!.completeError(Exception('no refresh token'));
        handler.next(err);
        return;
      }

      // Plain Dio for refresh: no interceptors, but shares the adapter so
      // tests can inject a fake one via setDio().
      final refreshDio = _buildPlainDio(err.requestOptions.baseUrl);

      final refreshResponse = await refreshDio.post<Map<String, dynamic>>(
        _refreshPath,
        data: {'refresh_token': refreshToken},
      );
      final data = refreshResponse.data;
      final newAccess = data?['access_token'] as String?;
      final newRefresh = data?['refresh_token'] as String?;

      if (newAccess == null || newRefresh == null) {
        await _tokenStorage.clearTokens();
        _refreshCompleter!.completeError(Exception('invalid refresh response'));
        handler.next(err);
        return;
      }

      await _tokenStorage.saveTokens(
        access: newAccess,
        refresh: newRefresh,
      );
      // Re-scope éventuel du token (contexte dérivé) avant de rejouer quoi
      // que ce soit — les 401 concurrents relisent le storage après coup.
      final hook = onTokensRefreshed;
      if (hook != null) {
        try {
          await hook(_buildPlainDio(err.requestOptions.baseUrl));
        } catch (_) {
          // Best-effort : un échec de re-scope ne doit pas invalider le
          // refresh (le token de base reste utilisable pour /auth/* et /me).
        }
      }
      // Signal all waiting 401s that new tokens are ready.
      _refreshCompleter!.complete();

      // Retry original request with the token now in storage (possibly
      // re-scoped by the hook above).
      final retryAccess = await _tokenStorage.getAccessToken() ?? newAccess;
      final retryOptions = err.requestOptions
        ..headers['Authorization'] = 'Bearer $retryAccess';

      final retryDio = _buildPlainDio(retryOptions.baseUrl);
      final retryResponse = await retryDio.fetch<dynamic>(retryOptions);
      handler.resolve(retryResponse);
    } on DioException {
      await _tokenStorage.clearTokens();
      _refreshCompleter!.completeError(Exception('refresh failed'));
      handler.next(err);
    } finally {
      _refreshCompleter = null;
    }
  }

  /// Builds a [Dio] instance with no interceptors that shares the same
  /// [HttpClientAdapter] (real or fake) as the parent [ApiClient].
  Dio _buildPlainDio(String baseUrl) {
    final dio = Dio(BaseOptions(baseUrl: baseUrl));
    final adapter = _httpClientAdapter;
    if (adapter != null) {
      dio.httpClientAdapter = adapter;
    }
    return dio;
  }
}
