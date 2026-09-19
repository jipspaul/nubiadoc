import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/session/pro_auth_cubit.dart';

class _MockLoginUseCase extends Mock implements LoginUseCase {}

class _MockLogoutUseCase extends Mock implements LogoutUseCase {}

class _MockTokenStorage extends Mock implements TokenStorage {}

class _MockDeviceRegistrationService extends Mock
    implements DeviceRegistrationService {}

class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

const _account = PatientAccount(
  id: 'user-1',
  firstName: 'Alice',
  lastName: 'Martin',
  email: 'alice@example.com',
);

void main() {
  late _MockLoginUseCase mockLogin;
  late _MockLogoutUseCase mockLogout;
  late _MockTokenStorage mockStorage;
  late _MockDeviceRegistrationService mockDeviceReg;
  late _MockApiClient mockApi;
  late _MockDio mockDio;

  setUp(() {
    mockLogin = _MockLoginUseCase();
    mockLogout = _MockLogoutUseCase();
    mockStorage = _MockTokenStorage();
    mockDeviceReg = _MockDeviceRegistrationService();
    mockApi = _MockApiClient();
    mockDio = _MockDio();

    when(() => mockDeviceReg.registerOnLogin(any())).thenAnswer((_) async {});
    when(() => mockApi.dio).thenReturn(mockDio);
    // #6170 : ProAuthCubit._session() interroge /me pour l'identité réelle en
    // best-effort au login — un échec ne doit jamais empêcher l'authentification.
    when(() => mockDio.get<Map<String, dynamic>>('/me'))
        .thenThrow(Exception('network'));
  });

  ProAuthCubit buildCubit() => ProAuthCubit(
        login: mockLogin,
        logout: mockLogout,
        tokenStorage: mockStorage,
        deviceRegistration: mockDeviceReg,
        api: mockApi,
        app: 'practicien',
      );

  group('ProAuthCubit.restore', () {
    setUp(() {
      when(() => mockStorage.getAccessToken())
          .thenAnswer((_) async => 'stored-token');
    });

    blocTest<ProAuthCubit, AuthState>(
      // #7397 : une coupure réseau au restore ne doit pas produire une
      // session fantôme aux libellés génériques (comportement pré-#7397) —
      // le token stocké n'a pas été invalidé, l'écran de démarrage doit
      // pouvoir proposer Réessayer au lieu d'une page vide indéfinie.
      "coupure réseau : émet AuthRestoreFailed, pas AuthAuthenticated",
      build: () {
        when(() => mockDio.get<Map<String, dynamic>>('/me')).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: '/me'),
            type: DioExceptionType.connectionError,
          ),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.restore(),
      expect: () => [isA<AuthRestoreFailed>()],
    );

    blocTest<ProAuthCubit, AuthState>(
      '401 (token réellement invalidé) : émet AuthUnauthenticated',
      build: () {
        when(() => mockDio.get<Map<String, dynamic>>('/me')).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: '/me'),
            response: Response(
              requestOptions: RequestOptions(path: '/me'),
              statusCode: 401,
            ),
          ),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.restore(),
      expect: () => [isA<AuthUnauthenticated>()],
    );

    blocTest<ProAuthCubit, AuthState>(
      'succès : émet AuthAuthenticated',
      build: () {
        when(() => mockDio.get<Map<String, dynamic>>('/me')).thenAnswer(
          (_) async => Response(
            data: {
              'user_id': 'a0000000-0000-0000-0000-0000000000a2',
              'memberships': <Map<String, dynamic>>[],
            },
            requestOptions: RequestOptions(path: '/me'),
          ),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.restore(),
      expect: () => [isA<AuthAuthenticated>()],
    );

    blocTest<ProAuthCubit, AuthState>(
      'pas de token stocké : émet AuthUnauthenticated sans appeler /me',
      build: () {
        when(() => mockStorage.getAccessToken())
            .thenAnswer((_) async => null);
        return buildCubit();
      },
      act: (cubit) => cubit.restore(),
      expect: () => [isA<AuthUnauthenticated>()],
      verify: (_) {
        verifyNever(() => mockDio.get<Map<String, dynamic>>('/me'));
      },
    );
  });

  group('ProAuthCubit.signIn', () {
    blocTest<ProAuthCubit, AuthState>(
      "succès : la session porte l'user_id retourné par /me",
      build: () {
        when(
          () => mockLogin(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => const Right(_account));
        when(() => mockDio.get<Map<String, dynamic>>('/me')).thenAnswer(
          (_) async => Response(
            data: {
              'user_id': 'a0000000-0000-0000-0000-0000000000a2',
              'memberships': <Map<String, dynamic>>[],
            },
            requestOptions: RequestOptions(path: '/me'),
          ),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.signIn(
        email: 'jean.dupont@cabinet-lyon.test',
        password: 's3cr3t',
      ),
      expect: () => [
        const AuthLoading(),
        isA<AuthAuthenticated>().having(
          (s) => s.session.userId,
          'session.userId',
          'a0000000-0000-0000-0000-0000000000a2',
        ),
      ],
    );

    blocTest<ProAuthCubit, AuthState>(
      'échec identifiants : émet AuthLoading puis AuthUnauthenticated',
      build: () {
        when(
          () => mockLogin(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer(
          (_) async => const Left(InvalidCredentialsFailure()),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.signIn(
        email: 'jean.dupont@cabinet-lyon.test',
        password: 'wrong',
      ),
      expect: () => [
        const AuthLoading(),
        isA<AuthUnauthenticated>(),
      ],
    );
  });
}
