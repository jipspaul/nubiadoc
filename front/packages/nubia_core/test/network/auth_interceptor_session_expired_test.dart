// Regression test for #6902 : un refresh échoué effaçait bien les tokens en
// storage, mais ne le signalait à personne — l'app restait sur la route
// protégée (coquille authentifiée) derrière des 401 en boucle. Le hook
// onSessionExpired est le signal que chaque app branche sur son AuthCubit
// (cf. app.dart) pour rediriger vers /login.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_core/src/network/auth_interceptor.dart';
import 'package:nubia_core/src/storage/token_storage.dart';

class FakeTokenStorage implements TokenStorage {
  String? access;
  String? refresh;
  FakeTokenStorage({this.access, this.refresh});

  @override
  Future<String?> getAccessToken() async => access;
  @override
  Future<String?> getRefreshToken() async => refresh;
  @override
  Future<String?> getFcmToken() async => null;
  @override
  Future<void> saveTokens(
      {required String access, required String refresh}) async {
    this.access = access;
    this.refresh = refresh;
  }

  @override
  Future<void> saveFcmToken(String token) async {}
  @override
  Future<void> clearTokens() async {
    access = null;
    refresh = null;
  }

  @override
  Future<void> clearFcmToken() async {}
}

class _AlwaysUnauthorizedAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"error":"unauthorized"}',
      401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'refresh token inconnu/rejeté (401 sur /auth/refresh) → onSessionExpired appelé',
    () async {
      final storage = FakeTokenStorage(access: 'expired', refresh: 'revoked');
      final interceptor = AuthInterceptor(storage);
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..interceptors.add(interceptor)
        ..httpClientAdapter = _AlwaysUnauthorizedAdapter();
      interceptor.setDio(dio);

      var sessionExpiredCalls = 0;
      interceptor.onSessionExpired = () => sessionExpiredCalls++;

      await expectLater(
          dio.get<dynamic>('/cabinet/agenda'), throwsA(isA<DioException>()));

      expect(storage.access, isNull);
      expect(sessionExpiredCalls, 1);
    },
  );

  test(
    'pas de refresh token en storage → onSessionExpired appelé',
    () async {
      final storage = FakeTokenStorage(access: 'expired', refresh: null);
      final interceptor = AuthInterceptor(storage);
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..interceptors.add(interceptor)
        ..httpClientAdapter = _AlwaysUnauthorizedAdapter();
      interceptor.setDio(dio);

      var sessionExpiredCalls = 0;
      interceptor.onSessionExpired = () => sessionExpiredCalls++;

      await expectLater(
          dio.get<dynamic>('/me'), throwsA(isA<DioException>()));

      expect(sessionExpiredCalls, 1);
    },
  );
}
