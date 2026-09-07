// #6682 : le refresh renvoie un token de login kind:"pro" sans le contexte
// nurse — sans re-scope, /v1/nurse/* répond 403 en boucle après ~15 min alors
// que l'app ne se déconnecte pas (elle affiche un état incohérent). Ce test
// vérifie que signIn() retient le nurse_id sélectionné et que reselectContext
// (branché sur AuthInterceptor.onTokensRefreshed) l'utilise pour ré-échanger
// le token pro contre un token nurse, comme le fait déjà l'app pharmacie.
import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_infirmiere/session/infirmiere_auth_cubit.dart';

class MockLoginUseCase extends Mock implements LoginUseCase {}

class MockLogoutUseCase extends Mock implements LogoutUseCase {}

class MockDeviceRegistrationService extends Mock
    implements DeviceRegistrationService {}

class MockDio extends Mock implements Dio {}

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

/// GET /nurse/memberships → [{"nurse_id": "n1"}] ; POST
/// /auth/select-nurse-context → un token "nurseToken1".
class ScriptedNurseAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/nurse/memberships') {
      return ResponseBody.fromString(
        '[{"nurse_id":"n1"}]',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.path == '/auth/select-nurse-context') {
      return ResponseBody.fromString(
        '{"access_token":"nurseToken1"}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      '{"error":"not_found"}',
      404,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      Options(headers: const {'Authorization': 'Bearer fallback'}),
    );
  });

  late MockLoginUseCase login;
  late MockLogoutUseCase logout;
  late FakeTokenStorage tokenStorage;
  late MockDeviceRegistrationService deviceRegistration;
  late AuthInterceptor authInterceptor;
  late ApiClient api;

  final account =
      PatientAccount(id: '', firstName: '', lastName: '', email: 'i@o.fr');

  setUp(() {
    login = MockLoginUseCase();
    logout = MockLogoutUseCase();
    tokenStorage = FakeTokenStorage(access: 'proToken', refresh: 'refreshR');
    deviceRegistration = MockDeviceRegistrationService();
    authInterceptor = AuthInterceptor(tokenStorage);
    api = ApiClient(authInterceptor)
      ..dio.httpClientAdapter = ScriptedNurseAdapter();

    when(() =>
            login(email: any(named: 'email'), password: any(named: 'password')))
        .thenAnswer((_) async => Right(account));
    when(() => deviceRegistration.registerOnLogin(any()))
        .thenAnswer((_) async {});
  });

  InfirmiereAuthCubit buildCubit() => InfirmiereAuthCubit(
        login: login,
        logout: logout,
        tokenStorage: tokenStorage,
        deviceRegistration: deviceRegistration,
        api: api,
      );

  test('reselectContext est un no-op tant qu\'aucun contexte n\'a été sélectionné',
      () async {
    final cubit = buildCubit();
    final plainDio = MockDio();

    await cubit.reselectContext(plainDio);

    verifyZeroInteractions(plainDio);
  });

  test(
      'signIn retient le nurse_id, reselectContext le rejoue après un refresh',
      () async {
    final cubit = buildCubit();

    await cubit.signIn(email: 'i@o.fr', password: 'secret');

    expect(cubit.state, isA<AuthAuthenticated>());
    // select-nurse-context a bien re-scopé le token en storage au login.
    expect(tokenStorage.access, 'nurseToken1');

    // Simule le token de base (kind:"pro") réécrit par un /auth/refresh.
    tokenStorage.access = 'proTokenRefreshed';

    final plainDio = MockDio();
    when(() => plainDio.post<Map<String, dynamic>>(
          '/auth/select-nurse-context',
          data: any(named: 'data'),
          options: any(named: 'options'),
        )).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/auth/select-nurse-context'),
        statusCode: 200,
        data: const {'access_token': 'nurseToken2'},
      ),
    );

    await cubit.reselectContext(plainDio);

    expect(tokenStorage.access, 'nurseToken2');
    expect(tokenStorage.refresh, 'refreshR');
    final captured = verify(() => plainDio.post<Map<String, dynamic>>(
          '/auth/select-nurse-context',
          data: captureAny(named: 'data'),
          options: captureAny(named: 'options'),
        )).captured;
    expect(captured.first, {'nurse_id': 'n1'});
    expect(
      (captured.last as Options).headers?['Authorization'],
      'Bearer proTokenRefreshed',
    );
  });
}
