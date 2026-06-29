import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/register/pro_register_cubit.dart';
import 'package:app_practicien/session/pro_auth_cubit.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockProRegisterUseCase extends Mock implements ProRegisterUseCase {}

class MockProAuthCubit extends MockCubit<AuthState> implements ProAuthCubit {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _request = ProRegisterRequest(
  email: 'alice@example.com',
  password: 'secret',
  inviteToken: 'tok-xyz',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockProRegisterUseCase mockRegister;
  late MockProAuthCubit mockAuth;

  setUpAll(() {
    registerFallbackValue(_request);
  });

  setUp(() {
    mockRegister = MockProRegisterUseCase();
    mockAuth = MockProAuthCubit();
  });

  ProRegisterCubit makeCubit() =>
      ProRegisterCubit(register: mockRegister, authCubit: mockAuth);

  group('ProRegisterCubit', () {
    blocTest<ProRegisterCubit, ProRegisterState>(
      'émet [Loading, Success] et appelle restore() sur succès',
      build: () {
        when(() => mockRegister(any()))
            .thenAnswer((_) async => const Right('account-1'));
        when(() => mockAuth.restore()).thenAnswer((_) async {});
        return makeCubit();
      },
      act: (c) => c.submit(_request),
      expect: () => [
        isA<ProRegisterLoading>(),
        isA<ProRegisterSuccess>()
            .having((s) => s.accountId, 'accountId', 'account-1'),
      ],
      verify: (_) => verify(() => mockAuth.restore()).called(1),
    );

    blocTest<ProRegisterCubit, ProRegisterState>(
      'émet [Loading, Failure] quand e-mail déjà utilisé (409)',
      build: () {
        when(() => mockRegister(any())).thenAnswer(
          (_) async => const Left(
            ServerFailure(message: 'E-mail déjà utilisé.', statusCode: 409),
          ),
        );
        return makeCubit();
      },
      act: (c) => c.submit(_request),
      expect: () => [
        isA<ProRegisterLoading>(),
        isA<ProRegisterFailure>()
            .having((s) => s.message, 'message', 'E-mail déjà utilisé.'),
      ],
    );

    blocTest<ProRegisterCubit, ProRegisterState>(
      'émet [Loading, Failure] sur erreur réseau',
      build: () {
        when(() => mockRegister(any())).thenAnswer(
          (_) async => const Left(NetworkFailure()),
        );
        return makeCubit();
      },
      act: (c) => c.submit(_request),
      expect: () => [
        isA<ProRegisterLoading>(),
        isA<ProRegisterFailure>().having(
          (s) => s.message,
          'message',
          'Erreur réseau. Vérifiez votre connexion.',
        ),
      ],
    );
  });
}
