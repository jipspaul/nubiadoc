import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/network/auth_interceptor.dart';
import 'package:nubia_patient/core/storage/token_storage.dart';

class MockTokenStorage extends Mock implements TokenStorage {}

/// A minimal [HttpClientAdapter] that records requests and returns canned responses.
class _FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> capturedRequests = [];
  // Map path → ResponseBody to return.
  final Map<String, ResponseBody> responses;

  _FakeAdapter(this.responses);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    capturedRequests.add(options);
    final body = responses[options.path];
    if (body != null) return body;
    // Default: 200 empty JSON
    return ResponseBody.fromString('{}', 200,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late MockTokenStorage tokenStorage;
  late AuthInterceptor interceptor;

  setUp(() {
    tokenStorage = MockTokenStorage();
    interceptor = AuthInterceptor(tokenStorage);
  });

  group('AuthInterceptor', () {
    test('attaches Bearer token to every request', () async {
      when(() => tokenStorage.getAccessToken())
          .thenAnswer((_) async => 'access-abc');

      final options = RequestOptions(path: '/appointments');
      final handler = RequestInterceptorHandler();

      await interceptor.onRequest(options, handler);

      expect(options.headers['Authorization'], 'Bearer access-abc');
    });

    test('does not attach Authorization when no token stored', () async {
      when(() => tokenStorage.getAccessToken()).thenAnswer((_) async => null);

      final options = RequestOptions(path: '/appointments');
      final handler = RequestInterceptorHandler();

      await interceptor.onRequest(options, handler);

      expect(options.headers.containsKey('Authorization'), isFalse);
    });

    test('on 401: calls refresh and retries original request', () async {
      // Arrange
      const newAccess = 'new-access-xyz';
      const newRefresh = 'new-refresh-xyz';

      when(() => tokenStorage.getRefreshToken())
          .thenAnswer((_) async => 'old-refresh');
      when(() => tokenStorage.saveTokens(
            access: newAccess,
            refresh: newRefresh,
          )).thenAnswer((_) async {});

      // Build a Dio that owns the interceptor and use a fake adapter.
      final dio = Dio(BaseOptions(baseUrl: 'https://api.nubia.health/v1'));
      final fakeAdapter = _FakeAdapter({
        '/auth/refresh': ResponseBody.fromString(
          '{"access_token":"$newAccess","refresh_token":"$newRefresh"}',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          },
        ),
        '/appointments': ResponseBody.fromString(
          '[]',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          },
        ),
      });
      dio.httpClientAdapter = fakeAdapter;
      dio.interceptors.add(interceptor);

      // Simulate 401 on /appointments
      final requestOptions = RequestOptions(
        path: '/appointments',
        baseUrl: 'https://api.nubia.health/v1',
      );
      final dioError = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 401,
        ),
        type: DioExceptionType.badResponse,
      );
      final handler = ErrorInterceptorHandler();

      await interceptor.onError(dioError, handler);

      // Refresh was called
      verify(() => tokenStorage.saveTokens(
            access: newAccess,
            refresh: newRefresh,
          )).called(1);

      // Retry request was made
      final paths = fakeAdapter.capturedRequests.map((r) => r.path).toList();
      expect(paths, contains('/auth/refresh'));
      expect(paths, contains('/appointments'));
    });

    test('on 401 with no refresh token: clears tokens and forwards error',
        () async {
      when(() => tokenStorage.getRefreshToken()).thenAnswer((_) async => null);
      when(() => tokenStorage.clearTokens()).thenAnswer((_) async {});

      final requestOptions = RequestOptions(
        path: '/appointments',
        baseUrl: 'https://api.nubia.health/v1',
      );
      final dioError = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 401,
        ),
        type: DioExceptionType.badResponse,
      );
      final handler = ErrorInterceptorHandler();

      await interceptor.onError(dioError, handler);

      verify(() => tokenStorage.clearTokens()).called(1);
    });

    test('does not intercept 401 on /auth/refresh (avoids infinite loop)',
        () async {
      when(() => tokenStorage.getRefreshToken())
          .thenAnswer((_) async => 'refresh-token');

      final requestOptions = RequestOptions(
        path: '/auth/refresh',
        baseUrl: 'https://api.nubia.health/v1',
      );
      final dioError = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 401,
        ),
        type: DioExceptionType.badResponse,
      );
      final handler = ErrorInterceptorHandler();

      await interceptor.onError(dioError, handler);

      // getRefreshToken must NOT be called — the interceptor bails early.
      verifyNever(() => tokenStorage.getRefreshToken());
    });
  });
}
