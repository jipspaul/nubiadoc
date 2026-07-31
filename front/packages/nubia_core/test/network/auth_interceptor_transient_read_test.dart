// Regression test for #4533 : un GET /v1/me en 401 déconnectait l'app
// SANS jamais appeler /auth/refresh, alors qu'un refresh token valide était
// bien présent en storage l'instant d'après — un read transitoirement `null`
// (storage pas encore prêt) faisait abandonner le refresh au lieu de retenter.
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_core/src/network/auth_interceptor.dart';
import 'package:nubia_core/src/storage/token_storage.dart';

/// TokenStorage fake dont `getRefreshToken()` renvoie `null` les
/// [nullReadsBeforeSuccess] premières fois avant de trouver le vrai token —
/// simule le read transitoirement vide observé sur web.
class FlakyTokenStorage implements TokenStorage {
  FlakyTokenStorage({
    required this.access,
    required this.refresh,
    required this.nullReadsBeforeSuccess,
  });

  String? access;
  final String refresh;
  int nullReadsBeforeSuccess;
  int refreshReadCount = 0;

  @override
  Future<String?> getAccessToken() async => access;

  @override
  Future<String?> getRefreshToken() async {
    refreshReadCount++;
    if (refreshReadCount <= nullReadsBeforeSuccess) return null;
    return refresh;
  }

  @override
  Future<String?> getFcmToken() async => null;

  @override
  Future<void> saveTokens({required String access, required String refresh}) async {
    this.access = access;
  }

  @override
  Future<void> saveFcmToken(String token) async {}

  @override
  Future<void> clearTokens() async {
    access = null;
  }

  @override
  Future<void> clearFcmToken() async {}
}

class _ScriptedAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/auth/refresh') {
      return ResponseBody.fromString(
        '{"access_token":"newAccess","refresh_token":"newRefresh"}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.headers['Authorization'] == 'Bearer newAccess') {
      return ResponseBody.fromString(
        '{"ok":true}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
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
    'read du refresh token transitoirement null → retenté, refresh tenté quand même',
    () async {
      final storage = FlakyTokenStorage(
        access: 'expired',
        refresh: 'validRefresh',
        nullReadsBeforeSuccess: 2,
      );
      final interceptor = AuthInterceptor(storage);
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..interceptors.add(interceptor)
        ..httpClientAdapter = _ScriptedAdapter();
      interceptor.setDio(dio);

      final response = await dio.get<dynamic>('/v1/me');

      expect(response.statusCode, 200,
          reason: '401 aurait dû déclencher un refresh réussi malgré le '
              'read transitoirement null, pas propager l\'erreur');
      expect(storage.access, 'newAccess');
    },
  );

  test(
    'refresh token réellement absent après retries → déconnexion (comportement inchangé)',
    () async {
      final storage = FlakyTokenStorage(
        access: 'expired',
        refresh: 'neverUsed',
        nullReadsBeforeSuccess: 999, // jamais résolu → vraie absence
      );
      final interceptor = AuthInterceptor(storage);
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..interceptors.add(interceptor)
        ..httpClientAdapter = _ScriptedAdapter();
      interceptor.setDio(dio);

      await expectLater(dio.get<dynamic>('/v1/me'), throwsA(isA<DioException>()));
      expect(storage.access, isNull, reason: 'tokens effacés — vraie absence, pas une race');
    },
  );
}
