// #6964 : sur le web, `Geolocator.requestPermission()` s'adosse à l'invite
// navigateur — tant qu'elle n'est pas répondue, sa Future ne se règle jamais.
// `setOnline()` attendait cette Future avant tout PATCH : le clic sur « En
// ligne » restait inerte indéfiniment (0 requête, 0 message). Ce test simule
// exactement ce blocage (une Future de permission qui ne se résout jamais) et
// vérifie que `setOnline` aboutit quand même, sans lat/lng, dans un délai
// borné.
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:nubia_core/nubia_core.dart';

import 'package:app_infirmiere/features/nurse/nurse_cubit.dart';

class FakeTokenStorage implements TokenStorage {
  @override
  Future<String?> getAccessToken() async => 'nurseToken';
  @override
  Future<String?> getRefreshToken() async => 'refreshToken';
  @override
  Future<String?> getFcmToken() async => null;
  @override
  Future<void> saveTokens({required String access, required String refresh}) async {}
  @override
  Future<void> saveFcmToken(String token) async {}
  @override
  Future<void> clearTokens() async {}
  @override
  Future<void> clearFcmToken() async {}
}

/// Reproduit l'invite navigateur jamais répondue : `checkPermission()` répond
/// `denied`, puis `requestPermission()` renvoie une Future qui ne se règle
/// jamais (comme le prompt web tant qu'il n'est pas cliqué).
class _HangingPermissionGeolocatorPlatform extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied;

  @override
  Future<LocationPermission> requestPermission() =>
      Completer<LocationPermission>().future;
}

/// Capture les requêtes émises par le Dio du cubit pour vérifier le PATCH
/// `/nurse/availability` (et l'absence de `lat`/`lng`).
class RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late RecordingAdapter adapter;
  late NurseCubit cubit;

  setUp(() {
    GeolocatorPlatform.instance = _HangingPermissionGeolocatorPlatform();
    adapter = RecordingAdapter();
    final api = ApiClient(AuthInterceptor(FakeTokenStorage()))
      ..dio.httpClientAdapter = adapter;
    cubit = NurseCubit(api);
  });

  tearDown(() => cubit.close());

  test(
      'setOnline aboutit malgré une Future de géolocalisation qui ne se '
      'règle jamais (#6964)', () async {
    await cubit.setOnline(true).timeout(const Duration(seconds: 10));

    final patch = adapter.requests
        .where((r) => r.path == '/nurse/availability' && r.method == 'PATCH')
        .single;
    expect(patch.data, containsPair('is_online', true));
    expect((patch.data as Map).containsKey('lat'), isFalse);
    expect((patch.data as Map).containsKey('lng'), isFalse);

    expect(cubit.state.online, isTrue);
  });
}
