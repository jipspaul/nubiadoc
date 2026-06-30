import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/signup/signup_cubit.dart';
import 'package:app_patient/session/auth_cubit.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockRegisterUseCase extends Mock implements RegisterUseCase {}

class MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _account = PatientAccount(
  id: 'p-1',
  firstName: 'Alice',
  lastName: 'Dupont',
  email: 'alice@example.com',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockRegisterUseCase mockRegister;
  late MockAuthCubit mockAuth;

  setUp(() {
    mockRegister = MockRegisterUseCase();
    mockAuth = MockAuthCubit();
  });

  SignupCubit makeCubit() =>
      SignupCubit(register: mockRegister, authCubit: mockAuth);

  group('SignupCubit', () {
    blocTest<SignupCubit, SignupState>(
      'émet [Loading, Success] et appelle restore() sur succès',
      build: () {
        when(
          () => mockRegister(
            email: any(named: 'email'),
            password: any(named: 'password'),
            acceptCgu: any(named: 'acceptCgu'),
            cguVersion: any(named: 'cguVersion'),
          ),
        ).thenAnswer((_) async => const Right(_account));
        when(() => mockAuth.restore()).thenAnswer((_) async {});
        return makeCubit();
      },
      act: (c) =>
          c.register('alice@example.com', 'secret', acceptCgu: true),
      expect: () => [isA<SignupLoading>(), isA<SignupSuccess>()],
      verify: (_) => verify(() => mockAuth.restore()).called(1),
    );

    blocTest<SignupCubit, SignupState>(
      'émet [Loading, Failure] quand e-mail déjà utilisé (409)',
      build: () {
        when(
          () => mockRegister(
            email: any(named: 'email'),
            password: any(named: 'password'),
            acceptCgu: any(named: 'acceptCgu'),
            cguVersion: any(named: 'cguVersion'),
          ),
        ).thenAnswer(
          (_) async => const Left(
            ServerFailure(
              message: 'E-mail déjà utilisé.',
              statusCode: 409,
            ),
          ),
        );
        return makeCubit();
      },
      act: (c) =>
          c.register('alice@example.com', 'secret', acceptCgu: true),
      expect: () => [
        isA<SignupLoading>(),
        isA<SignupFailure>()
            .having((s) => s.message, 'message', 'E-mail déjà utilisé.'),
      ],
    );

    blocTest<SignupCubit, SignupState>(
      'émet [Loading, Failure] sur erreur réseau',
      build: () {
        when(
          () => mockRegister(
            email: any(named: 'email'),
            password: any(named: 'password'),
            acceptCgu: any(named: 'acceptCgu'),
            cguVersion: any(named: 'cguVersion'),
          ),
        ).thenAnswer(
          (_) async => const Left(NetworkFailure()),
        );
        return makeCubit();
      },
      act: (c) =>
          c.register('alice@example.com', 'secret', acceptCgu: true),
      expect: () => [
        isA<SignupLoading>(),
        isA<SignupFailure>().having(
          (s) => s.message,
          'message',
          'Erreur réseau. Vérifiez votre connexion.',
        ),
      ],
    );
  });
}
