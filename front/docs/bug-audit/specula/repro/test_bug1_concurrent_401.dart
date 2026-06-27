// Reproduction test for BUG-1: concurrent 401s dropped during token refresh.
// auth_interceptor.dart:49-52 — sibling 401s that arrive while _isRefreshing
// is true are completed with handler.next(err) and never retried under the
// refreshed token. Only the request that won the refresh lock is retried.
//
// Level 0 (pure black-box): drives the REAL AuthInterceptor through Dio's
// public API. No code modification, no timing hacks. The fake HttpClientAdapter
// replies 401 to the expired bearer, 200 to the refresh, 200 to a retry that
// carries the new bearer. Correct behaviour = all 3 requests succeed.
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_core/src/network/auth_interceptor.dart';
import 'package:nubia_core/src/storage/token_storage.dart';

/// In-memory TokenStorage fake (avoids FlutterSecureStorage / platform).
class FakeTokenStorage implements TokenStorage {
  String? access;
  String? refresh;
  String? fcm;
  FakeTokenStorage({this.access, this.refresh});

  @override
  Future<String?> getAccessToken() async => access;
  @override
  Future<String?> getRefreshToken() async => refresh;
  @override
  Future<String?> getFcmToken() async => fcm;
  @override
  Future<void> saveTokens(
      {required String access, required String refresh}) async {
    this.access = access;
    this.refresh = refresh;
  }

  @override
  Future<void> saveFcmToken(String token) async => fcm = token;
  @override
  Future<void> clearTokens() async {
    access = null;
    refresh = null;
  }

  @override
  Future<void> clearFcmToken() async => fcm = null;
}

/// Scripted adapter: expired bearer -> 401; /auth/refresh -> 200 (new tokens);
/// retry carrying the new bearer -> 200.
class ScriptedAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final auth = options.headers['Authorization'];
    if (options.path == '/auth/refresh') {
      return ResponseBody.fromString(
        '{"access_token":"newAccess","refresh_token":"newRefresh"}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      );
    }
    if (auth == 'Bearer newAccess') {
      return ResponseBody.fromString('{"ok":true}', 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });
    }
    // Expired bearer.
    return ResponseBody.fromString('{"error":"unauthorized"}', 401, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('concurrent 401s should all be retried after a successful refresh',
      () async {
    final storage =
        FakeTokenStorage(access: 'expired', refresh: 'validRefresh');
    final interceptor = AuthInterceptor(storage);

    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..interceptors.add(interceptor)
      ..httpClientAdapter = ScriptedAdapter();
    interceptor.setDio(dio);

    // Fire three requests concurrently — all sent with the (expired) token.
    final results = await Future.wait(
      ['/a', '/b', '/c'].map((p) async {
        try {
          final r = await dio.get<dynamic>(p);
          return r.statusCode == 200;
        } on DioException {
          return false;
        }
      }),
      eagerError: false,
    );

    final ok = results.where((s) => s).length;
    // ignore: avoid_print
    print('REPRO BUG-1: $ok/3 concurrent requests succeeded after refresh '
        '(correct = 3; bug drops the siblings that raced the refresh).');

    // Correct behaviour: a successful refresh should let ALL requests retry.
    expect(ok, 3,
        reason: 'concurrent 401s were dropped instead of retried '
            '(auth_interceptor.dart:49-52)');
  });
}
