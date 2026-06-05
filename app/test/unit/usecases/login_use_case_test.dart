import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';
import 'package:nubia_patient/domain/repositories/auth_repository.dart';
import 'package:nubia_patient/domain/usecases/auth/login_use_case.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

PatientAccount _makeAccount() => const PatientAccount(
      id: 'u1',
      firstName: 'Camille',
      lastName: 'Dupont',
      email: 'camille@example.com',
    );

void main() {
  late MockAuthRepository repository;
  late LoginUseCase useCase;

  setUp(() {
    repository = MockAuthRepository();
    useCase = LoginUseCase(repository);
  });

  group('LoginUseCase', () {
    test('returns PatientAccount on success', () async {
      final account = _makeAccount();
      when(
        () => repository.login(
          email: 'camille@example.com',
          password: 'secret',
        ),
      ).thenAnswer((_) async => Right(account));

      final result = await useCase(
        email: 'camille@example.com',
        password: 'secret',
      );

      expect(result, Right<Failure, PatientAccount>(account));
      verify(
        () => repository.login(
          email: 'camille@example.com',
          password: 'secret',
        ),
      ).called(1);
    });

    test('returns ValidationFailure for invalid email', () async {
      final result = await useCase(email: 'not-an-email', password: 'secret');

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<ValidationFailure>()),
        (_) => fail('expected failure'),
      );
      verifyNever(
        () => repository.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      );
    });

    test('returns ServerFailure on wrong password (from repository)', () async {
      when(
        () => repository.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async => const Left(
          ServerFailure(
            message: 'Email ou mot de passe incorrect.',
            statusCode: 401,
          ),
        ),
      );

      final result = await useCase(
        email: 'camille@example.com',
        password: 'wrong',
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<ServerFailure>()),
        (_) => fail('expected failure'),
      );
    });
  });
}
