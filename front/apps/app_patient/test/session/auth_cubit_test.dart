import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/session/auth_cubit.dart';

class MockLoginUseCase extends Mock implements LoginUseCase {}

class MockGetAccountUseCase extends Mock implements GetAccountUseCase {}

class MockLogoutUseCase extends Mock implements LogoutUseCase {}

class MockTokenStorage extends Mock implements TokenStorage {}

class MockDeviceRegistrationService extends Mock
    implements DeviceRegistrationService {}

void main() {
  late MockLoginUseCase login;
  late MockGetAccountUseCase getAccount;
  late MockLogoutUseCase logout;
  late MockTokenStorage tokenStorage;
  late MockDeviceRegistrationService deviceRegistration;

  // Placeholder retourné par /auth/login (pas d'account imbriqué dans la
  // réponse), voir AuthRepositoryImpl.login.
  const loginPlaceholder =
      PatientAccount(id: '', firstName: '', lastName: '', email: 'p@o.fr');
  const realAccount = PatientAccount(
    id: 'acct-1',
    firstName: 'Marc',
    lastName: 'Dubois',
    email: 'p@o.fr',
  );

  AuthCubit buildCubit() => AuthCubit(
        login: login,
        getAccount: getAccount,
        logout: logout,
        tokenStorage: tokenStorage,
        deviceRegistration: deviceRegistration,
      );

  setUp(() {
    login = MockLoginUseCase();
    getAccount = MockGetAccountUseCase();
    logout = MockLogoutUseCase();
    tokenStorage = MockTokenStorage();
    deviceRegistration = MockDeviceRegistrationService();

    when(() =>
            login(email: any(named: 'email'), password: any(named: 'password')))
        .thenAnswer((_) async => const Right(loginPlaceholder));
    when(() => getAccount()).thenAnswer((_) async => const Right(realAccount));
    when(() => deviceRegistration.registerOnLogin(any()))
        .thenAnswer((_) async {});
  });

  group('signIn', () {
    // #6141/#6178 : /auth/login ne renvoie qu'un compte placeholder (nom
    // vide) et /me ne renvoie jamais first_name/last_name ; le displayName
    // de la session doit venir de GET /account (getAccount), sinon
    // patient_display_name reste vide pour toute la session.
    blocTest<AuthCubit, AuthState>(
      'login réussi → displayName vient de getAccount(), pas du placeholder',
      build: buildCubit,
      act: (cubit) => cubit.signIn(email: 'p@o.fr', password: 'x'),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>().having(
          (s) => s.session.displayName,
          'displayName',
          'Marc Dubois',
        ),
      ],
      verify: (_) {
        verify(() => getAccount()).called(1);
        verify(() => deviceRegistration.registerOnLogin('patient')).called(1);
      },
    );

    blocTest<AuthCubit, AuthState>(
      'getAccount() échoue après login → repli sur le compte du login',
      build: buildCubit,
      setUp: () {
        when(() => getAccount())
            .thenAnswer((_) async => const Left(UnauthorizedFailure()));
      },
      act: (cubit) => cubit.signIn(email: 'p@o.fr', password: 'x'),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>().having(
          (s) => s.session.displayName,
          'displayName',
          loginPlaceholder.displayName,
        ),
      ],
    );

    blocTest<AuthCubit, AuthState>(
      'identifiants invalides → Unauthenticated, jamais de getAccount()',
      build: buildCubit,
      setUp: () {
        when(() => login(
                email: any(named: 'email'), password: any(named: 'password')))
            .thenAnswer((_) async => const Left(InvalidCredentialsFailure()));
      },
      act: (cubit) => cubit.signIn(email: 'p@o.fr', password: 'bad'),
      expect: () => [isA<AuthLoading>(), isA<AuthUnauthenticated>()],
      verify: (_) {
        verifyNever(() => getAccount());
        verifyNever(() => deviceRegistration.registerOnLogin(any()));
      },
    );
  });
}
