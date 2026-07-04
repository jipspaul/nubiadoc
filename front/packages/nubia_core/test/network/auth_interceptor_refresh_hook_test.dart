// Le refresh renvoie un token de login « de base » ; une app à contexte
// dérivé (app pharmacie, JWT kind:"pharma") enregistre onTokensRefreshed pour
// re-scoper le token avant que la requête d'origine soit rejouée. Le hook
// reçoit un Dio SANS interceptors (pas de réentrance sur le refresh en cours)
// et le retry doit porter le token laissé en storage par le hook.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_core/src/network/auth_interceptor.dart';
import 'package:nubia_core/src/storage/token_storage.dart';

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

/// expired → 401 ; /auth/refresh → newAccess ; retry : n'accepte QUE le token
/// re-scopé par le hook (un retry avec newAccess = échec du re-scope).
class ScriptedAdapter implements HttpClientAdapter {
  final List<String> retryBearers = [];

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
    final auth = options.headers['Authorization'] as String?;
    if (auth == 'Bearer scopedAccess') {
      retryBearers.add(auth!);
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
  test('onTokensRefreshed re-scope le token et le retry porte le token du hook',
      () async {
    final storage = FakeTokenStorage(access: 'expired', refresh: 'validR');
    final interceptor = AuthInterceptor(storage);
    final adapter = ScriptedAdapter();

    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..interceptors.add(interceptor)
      ..httpClientAdapter = adapter;
    interceptor.setDio(dio);

    Dio? hookDio;
    interceptor.onTokensRefreshed = (plainDio) async {
      hookDio = plainDio;
      // À ce stade le refresh a déjà persisté le token de base.
      expect(storage.access, 'newAccess');
      await storage.saveTokens(access: 'scopedAccess', refresh: 'validR');
    };

    final response = await dio.get<dynamic>('/pharmacy/orders');

    expect(response.statusCode, 200);
    expect(adapter.retryBearers, ['Bearer scopedAccess']);
    expect(storage.access, 'scopedAccess');
    expect(hookDio, isNotNull);
    expect(hookDio!.interceptors.whereType<AuthInterceptor>(), isEmpty,
        reason: 'le hook doit recevoir un Dio sans interceptors');
  });

  test('une erreur du hook n\'empêche pas le retry avec le token de base',
      () async {
    final storage = FakeTokenStorage(access: 'expired', refresh: 'validR');
    final interceptor = AuthInterceptor(storage);
    final adapter = _BaseTokenAdapter();

    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..interceptors.add(interceptor)
      ..httpClientAdapter = adapter;
    interceptor.setDio(dio);

    interceptor.onTokensRefreshed = (_) async {
      throw Exception('re-scope indisponible');
    };

    final response = await dio.get<dynamic>('/me');

    expect(response.statusCode, 200);
    expect(storage.access, 'newAccess');
  });
}

/// Variante qui accepte le token de base après refresh.
class _BaseTokenAdapter implements HttpClientAdapter {
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
    final auth = options.headers['Authorization'] as String?;
    if (auth == 'Bearer newAccess') {
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
