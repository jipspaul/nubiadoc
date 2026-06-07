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
  // Shared adapter injected by ApiClient so tests can swap it.
  HttpClientAdapter? _httpClientAdapter;

  AuthInterceptor(this._tokenStorage);

  /// Called by [ApiClient] after constructing [Dio], so tests can inject
  /// a fake [HttpClientAdapter] via the shared [Dio] instance.
  void setDio(Dio dio) => _httpClientAdapter = dio.httpClientAdapter;

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

      final retryDio = _buildPlainDio(retryOptions.baseUrl);
      final retryResponse = await retryDio.fetch<dynamic>(retryOptions);
      handler.resolve(retryResponse);
    } on DioException {
      await _tokenStorage.clearTokens();
      handler.next(err);
    } finally {
      _isRefreshing = false;
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
