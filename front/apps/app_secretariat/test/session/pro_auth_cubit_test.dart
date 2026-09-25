import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/session/pro_auth_cubit.dart';

class _MockLoginUseCase extends Mock implements LoginUseCase {}

class _MockLogoutUseCase extends Mock implements LogoutUseCase {}

class _MockRegisterUseCase extends Mock implements RegisterUseCase {}

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
  late _MockRegisterUseCase mockRegister;
  late _MockTokenStorage mockStorage;
  late _MockDeviceRegistrationService mockDeviceReg;
  late _MockApiClient mockApi;
  late _MockDio mockDio;

  setUp(() {
    mockLogin = _MockLoginUseCase();
    mockLogout = _MockLogoutUseCase();
    mockRegister = _MockRegisterUseCase();
    mockStorage = _MockTokenStorage();
    mockDeviceReg = _MockDeviceRegistrationService();
    mockApi = _MockApiClient();
    mockDio = _MockDio();

    when(() => mockDeviceReg.registerOnLogin(any())).thenAnswer((_) async {});
    when(() => mockApi.dio).thenReturn(mockDio);
    // #6170 : ProAuthCubit._session() interroge /me pour l'identité réelle en
    // best-effort — un échec ne doit jamais empêcher l'authentification.
    when(() => mockDio.get<Map<String, dynamic>>('/me'))
        .thenThrow(Exception('network'));
  });

  ProAuthCubit buildCubit() => ProAuthCubit(
        login: mockLogin,
        logout: mockLogout,
        register: mockRegister,
        tokenStorage: mockStorage,
        deviceRegistration: mockDeviceReg,
        api: mockApi,
        app: 'secretariat',
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
        when(() => mockStorage.getAccessToken()).thenAnswer((_) async => null);
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
      // #7346 : la session doit porter l'UUID réel de /me, pas le stub 'me' —
      // sinon assignee_id=me part sur les endpoints tâches et l'API rejette
      // en 400 (elle attend un Uuid, cf. api/src/cabinet_tasks.rs).
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
        email: 'sonia.accueil@cabinet-lyon.test',
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
  });

  group('ProAuthCubit.registerWithInvitation', () {
    blocTest<ProAuthCubit, AuthState>(
      'succès : émet AuthLoading puis AuthAuthenticated et appelle registerOnLogin',
      build: () {
        when(
          () => mockRegister(
            email: any(named: 'email'),
            password: any(named: 'password'),
            acceptCgu: any(named: 'acceptCgu'),
            cguVersion: any(named: 'cguVersion'),
            inviteToken: any(named: 'inviteToken'),
          ),
        ).thenAnswer((_) async => const Right(_account));
        return buildCubit();
      },
      act: (cubit) => cubit.registerWithInvitation(
        email: 'alice@example.com',
        password: 's3cr3t',
        inviteToken: 'tok-valid',
        acceptCgu: true,
      ),
      expect: () => [
        const AuthLoading(),
        isA<AuthAuthenticated>(),
      ],
      verify: (_) {
        verify(() => mockDeviceReg.registerOnLogin('secretariat')).called(1);
      },
    );

    blocTest<ProAuthCubit, AuthState>(
      'échec invitation invalide : émet AuthLoading puis AuthUnauthenticated',
      build: () {
        when(
          () => mockRegister(
            email: any(named: 'email'),
            password: any(named: 'password'),
            acceptCgu: any(named: 'acceptCgu'),
            cguVersion: any(named: 'cguVersion'),
            inviteToken: any(named: 'inviteToken'),
          ),
        ).thenAnswer(
          (_) async => const Left(
            ValidationFailure(message: "Jeton d'invitation manquant."),
          ),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.registerWithInvitation(
        email: 'alice@example.com',
        password: 's3cr3t',
        inviteToken: '',
        acceptCgu: true,
      ),
      expect: () => [
        const AuthLoading(),
        isA<AuthUnauthenticated>().having(
          (s) => s.message,
          'message',
          "Jeton d'invitation manquant.",
        ),
      ],
      verify: (_) {
        verifyNever(() => mockDeviceReg.registerOnLogin(any()));
      },
    );

    blocTest<ProAuthCubit, AuthState>(
      'échec réseau : émet AuthLoading puis AuthUnauthenticated avec message générique',
      build: () {
        when(
          () => mockRegister(
            email: any(named: 'email'),
            password: any(named: 'password'),
            acceptCgu: any(named: 'acceptCgu'),
            cguVersion: any(named: 'cguVersion'),
            inviteToken: any(named: 'inviteToken'),
          ),
        ).thenThrow(Exception('Erreur réseau'));
        return buildCubit();
      },
      act: (cubit) => cubit.registerWithInvitation(
        email: 'alice@example.com',
        password: 's3cr3t',
        inviteToken: 'tok-valid',
        acceptCgu: true,
      ),
      expect: () => [
        const AuthLoading(),
        isA<AuthUnauthenticated>().having(
          (s) => s.message,
          'message',
          "Erreur lors de l'inscription.",
        ),
      ],
      verify: (_) {
        verifyNever(() => mockDeviceReg.registerOnLogin(any()));
      },
    );
  });

  group('ProAuthCubit.registerWithInviteLink', () {
    blocTest<ProAuthCubit, AuthState>(
      'succès : émet AuthLoading puis AuthAuthenticated et appelle registerOnLogin',
      build: () {
        when(
          () => mockRegister(
            email: any(named: 'email'),
            password: any(named: 'password'),
            acceptCgu: any(named: 'acceptCgu'),
            cguVersion: any(named: 'cguVersion'),
            inviteLinkToken: any(named: 'inviteLinkToken'),
          ),
        ).thenAnswer((_) async => const Right(_account));
        return buildCubit();
      },
      act: (cubit) => cubit.registerWithInviteLink(
        email: 'alice@example.com',
        password: 's3cr3t',
        inviteLinkToken: 'link-tok-valid',
        acceptCgu: true,
      ),
      expect: () => [
        const AuthLoading(),
        isA<AuthAuthenticated>(),
      ],
      verify: (_) {
        verify(() => mockDeviceReg.registerOnLogin('secretariat')).called(1);
      },
    );

    blocTest<ProAuthCubit, AuthState>(
      'échec lien invalide/expiré : émet AuthLoading puis AuthUnauthenticated(invalidInvite)',
      build: () {
        when(
          () => mockRegister(
            email: any(named: 'email'),
            password: any(named: 'password'),
            acceptCgu: any(named: 'acceptCgu'),
            cguVersion: any(named: 'cguVersion'),
            inviteLinkToken: any(named: 'inviteLinkToken'),
          ),
        ).thenAnswer((_) async => const Left(InvalidInviteFailure()));
        return buildCubit();
      },
      act: (cubit) => cubit.registerWithInviteLink(
        email: 'alice@example.com',
        password: 's3cr3t',
        inviteLinkToken: 'link-tok-expired',
        acceptCgu: true,
      ),
      expect: () => [
        const AuthLoading(),
        isA<AuthUnauthenticated>().having(
          (s) => s.invalidInvite,
          'invalidInvite',
          true,
        ),
      ],
      verify: (_) {
        verifyNever(() => mockDeviceReg.registerOnLogin(any()));
      },
    );
  });
}
