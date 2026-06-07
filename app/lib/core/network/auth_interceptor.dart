import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/storage/token_storage.dart';

/// Injects Bearer JWT into every request.
/// Handles 401 → token refresh → retry (once).
/// On refresh failure → clears tokens (caller should redirect to login).
@injectable
class AuthInterceptor extends Interceptor {
  final TokenStorage _tokenStorage;
  // Sentinel path used internally for refresh calls — must not be intercepted.
  static const _refreshPath = '/auth/refresh';
  // Guard against re-entrant refresh (concurrent 401s).
  bool _isRefreshing = false;

  AuthInterceptor(this._tokenStorage);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokenStorage.getAccessToken();
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

    // Avoid re-entrant refresh on concurrent failures.
    if (_isRefreshing) {
      handler.next(err);
      return;
    }

    _isRefreshing = true;
    try {
      final refreshToken = await _tokenStorage.getRefreshToken();
      if (refreshToken == null) {
        await _tokenStorage.clearTokens();
        handler.next(err);
        return;
      }

      // Attempt refresh using a plain Dio instance (bypasses this interceptor).
      final refreshDio = Dio(
        BaseOptions(baseUrl: err.requestOptions.baseUrl),
      );
      final refreshResponse = await refreshDio.post<Map<String, dynamic>>(
        _refreshPath,
        data: {'refresh_token': refreshToken},
      );
      final data = refreshResponse.data;
      final newAccess = data?['access_token'] as String?;
      final newRefresh = data?['refresh_token'] as String?;

      if (newAccess == null || newRefresh == null) {
        await _tokenStorage.clearTokens();
        handler.next(err);
        return;
      }

      await _tokenStorage.saveTokens(
        access: newAccess,
        refresh: newRefresh,
      );

      // Retry original request with new access token.
      final retryOptions = err.requestOptions
        ..headers['Authorization'] = 'Bearer $newAccess';

      final retryDio = Dio(
        BaseOptions(baseUrl: retryOptions.baseUrl),
      );
      final retryResponse = await retryDio.fetch<dynamic>(retryOptions);
      handler.resolve(retryResponse);
    } on DioException {
      await _tokenStorage.clearTokens();
      handler.next(err);
    } finally {
      _isRefreshing = false;
    }
  }
}
