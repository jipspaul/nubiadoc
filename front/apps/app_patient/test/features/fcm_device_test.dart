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

class MockDeviceRegistrationService extends Mock
    implements DeviceRegistrationService {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _account = PatientAccount(
  id: 'user-1',
  firstName: 'Alice',
  lastName: 'Martin',
  email: 'alice@example.com',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockLoginUseCase mockLogin;
  late MockGetMeUseCase mockGetMe;
  late MockLogoutUseCase mockLogout;
  late MockTokenStorage mockStorage;
  late MockDeviceRegistrationService mockDeviceReg;

  setUp(() {
    mockLogin = MockLoginUseCase();
    mockGetMe = MockGetMeUseCase();
    mockLogout = MockLogoutUseCase();
    mockStorage = MockTokenStorage();
    mockDeviceReg = MockDeviceRegistrationService();

    when(() => mockDeviceReg.registerOnLogin(any())).thenAnswer((_) async {});
  });

  AuthCubit buildCubit() => AuthCubit(
        login: mockLogin,
        getMe: mockGetMe,
        logout: mockLogout,
        tokenStorage: mockStorage,
        deviceRegistration: mockDeviceReg,
      );

  group('AuthCubit — enregistrement FCM au login', () {
    blocTest<AuthCubit, AuthState>(
      'appelle DeviceRegistrationService.registerOnLogin après une connexion réussie',
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
        verify(() => mockDeviceReg.registerOnLogin('patient')).called(1);
      },
    );

    blocTest<AuthCubit, AuthState>(
      "émet AuthUnauthenticated si la connexion échoue (pas d'appel FCM)",
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
      act: (cubit) => cubit.signIn(email: 'bad@example.com', password: 'wrong'),
      expect: () => [
        const AuthLoading(),
        isA<AuthUnauthenticated>().having(
          (s) => s.message,
          'message',
          'Identifiants invalides.',
        ),
      ],
      verify: (_) {
        verifyNever(() => mockDeviceReg.registerOnLogin(any()));
      },
    );
  });
}
