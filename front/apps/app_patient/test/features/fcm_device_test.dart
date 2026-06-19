import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/session/auth_cubit.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockLoginUseCase extends Mock implements LoginUseCase {}

class MockGetMeUseCase extends Mock implements GetMeUseCase {}

class MockLogoutUseCase extends Mock implements LogoutUseCase {}

class MockTokenStorage extends Mock implements TokenStorage {}

class MockRegisterDeviceUseCase extends Mock implements RegisterDeviceUseCase {}

class MockFcmTokenProvider extends Mock implements FcmTokenProvider {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _account = PatientAccount(
  id: 'user-1',
  firstName: 'Alice',
  lastName: 'Martin',
  email: 'alice@example.com',
);

const _fcmToken = 'fcm-test-token-abc123';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockLoginUseCase mockLogin;
  late MockGetMeUseCase mockGetMe;
  late MockLogoutUseCase mockLogout;
  late MockTokenStorage mockStorage;
  late MockRegisterDeviceUseCase mockRegisterDevice;
  late MockFcmTokenProvider mockFcmProvider;

  setUp(() {
    mockLogin = MockLoginUseCase();
    mockGetMe = MockGetMeUseCase();
    mockLogout = MockLogoutUseCase();
    mockStorage = MockTokenStorage();
    mockRegisterDevice = MockRegisterDeviceUseCase();
    mockFcmProvider = MockFcmTokenProvider();

    // Default stubs
    when(() => mockFcmProvider.getToken())
        .thenAnswer((_) async => _fcmToken);
    when(() => mockFcmProvider.platform).thenReturn('android');
    when(
      () => mockRegisterDevice(
        fcmToken: any(named: 'fcmToken'),
        platform: any(named: 'platform'),
      ),
    ).thenAnswer((_) async => const Right(null));
  });

  AuthCubit buildCubit() => AuthCubit(
        login: mockLogin,
        getMe: mockGetMe,
        logout: mockLogout,
        tokenStorage: mockStorage,
        registerDevice: mockRegisterDevice,
        fcmTokenProvider: mockFcmProvider,
      );

  group('AuthCubit — enregistrement FCM au login', () {
    blocTest<AuthCubit, AuthState>(
      'appelle RegisterDeviceUseCase avec le token FCM après une connexion réussie',
      build: () {
        when(
          () => mockLogin(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => const Right(_account));
        return buildCubit();
      },
      act: (cubit) =>
          cubit.signIn(email: 'alice@example.com', password: 's3cr3t'),
      expect: () => [
        const AuthLoading(),
        isA<AuthAuthenticated>().having(
          (s) => s.session.userId,
          'userId',
          'user-1',
        ),
      ],
      verify: (_) {
        verify(
          () => mockRegisterDevice(
            fcmToken: _fcmToken,
            platform: 'android',
          ),
        ).called(1);
      },
    );

    blocTest<AuthCubit, AuthState>(
      'ne panique pas si le provider FCM renvoie null (pas de token dispo)',
      build: () {
        when(() => mockFcmProvider.getToken()).thenAnswer((_) async => null);
        when(
          () => mockLogin(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => const Right(_account));
        return buildCubit();
      },
      act: (cubit) =>
          cubit.signIn(email: 'alice@example.com', password: 's3cr3t'),
      expect: () => [
        const AuthLoading(),
        isA<AuthAuthenticated>(),
      ],
      verify: (_) {
        verifyNever(
          () => mockRegisterDevice(
            fcmToken: any(named: 'fcmToken'),
            platform: any(named: 'platform'),
          ),
        );
      },
    );

    blocTest<AuthCubit, AuthState>(
      'émet AuthUnauthenticated si la connexion échoue (pas d\'appel FCM)',
      build: () {
        when(
          () => mockLogin(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer(
          (_) async =>
              const Left(ServerFailure(message: 'Identifiants invalides.')),
        );
        return buildCubit();
      },
      act: (cubit) =>
          cubit.signIn(email: 'bad@example.com', password: 'wrong'),
      expect: () => [
        const AuthLoading(),
        isA<AuthUnauthenticated>().having(
          (s) => s.message,
          'message',
          'Identifiants invalides.',
        ),
      ],
      verify: (_) {
        verifyNever(
          () => mockRegisterDevice(
            fcmToken: any(named: 'fcmToken'),
            platform: any(named: 'platform'),
          ),
        );
      },
    );
  });
}
