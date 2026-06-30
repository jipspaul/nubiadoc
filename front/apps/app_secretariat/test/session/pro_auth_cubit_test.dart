import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
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

  setUp(() {
    mockLogin = _MockLoginUseCase();
    mockLogout = _MockLogoutUseCase();
    mockRegister = _MockRegisterUseCase();
    mockStorage = _MockTokenStorage();
    mockDeviceReg = _MockDeviceRegistrationService();

    when(() => mockDeviceReg.registerOnLogin(any())).thenAnswer((_) async {});
  });

  ProAuthCubit buildCubit() => ProAuthCubit(
        login: mockLogin,
        logout: mockLogout,
        register: mockRegister,
        tokenStorage: mockStorage,
        deviceRegistration: mockDeviceReg,
        app: 'secretariat',
      );

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
}
