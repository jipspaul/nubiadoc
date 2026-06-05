import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';
import 'package:nubia_patient/domain/repositories/auth_repository.dart';
import 'package:nubia_patient/domain/usecases/auth/register_use_case.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

PatientAccount _makeAccount() => const PatientAccount(
      id: 'u1',
      firstName: 'Camille',
      lastName: 'Dupont',
      email: 'camille@example.com',
    );

void main() {
  late MockAuthRepository repository;
  late RegisterUseCase useCase;

  setUp(() {
    repository = MockAuthRepository();
    useCase = RegisterUseCase(repository);
  });

  group('RegisterUseCase', () {
    test('returns PatientAccount on success', () async {
      final account = _makeAccount();
      when(
        () => repository.register(
          email: 'camille@example.com',
          password: 'secret',
          inviteToken: 'tok123',
        ),
      ).thenAnswer((_) async => Right(account));

      final result = await useCase(
        email: 'camille@example.com',
        password: 'secret',
        inviteToken: 'tok123',
      );

      expect(result, Right<Failure, PatientAccount>(account));
      verify(
        () => repository.register(
          email: 'camille@example.com',
          password: 'secret',
          inviteToken: 'tok123',
        ),
      ).called(1);
    });

    test('returns ValidationFailure when invite token is empty', () async {
      final result = await useCase(
        email: 'camille@example.com',
        password: 'secret',
        inviteToken: '',
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<ValidationFailure>()),
        (_) => fail('expected failure'),
      );
      verifyNever(
        () => repository.register(
          email: any(named: 'email'),
          password: any(named: 'password'),
          inviteToken: any(named: 'inviteToken'),
        ),
      );
    });

    test('returns ServerFailure when invite is expired (from repository)', () async {
      when(
        () => repository.register(
          email: any(named: 'email'),
          password: any(named: 'password'),
          inviteToken: any(named: 'inviteToken'),
        ),
      ).thenAnswer(
        (_) async => const Left(
          ServerFailure(
            message: "Jeton d'invitation expiré.",
            statusCode: 422,
            code: 'invite_expired',
          ),
        ),
      );

      final result = await useCase(
        email: 'camille@example.com',
        password: 'secret',
        inviteToken: 'expired-tok',
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<ServerFailure>()),
        (_) => fail('expected failure'),
      );
    });

    test('returns ServerFailure when email already in use (from repository)', () async {
      when(
        () => repository.register(
          email: any(named: 'email'),
          password: any(named: 'password'),
          inviteToken: any(named: 'inviteToken'),
        ),
      ).thenAnswer(
        (_) async => const Left(
          ServerFailure(
            message: 'Cette adresse e-mail est déjà utilisée.',
            statusCode: 409,
            code: 'email_conflict',
          ),
        ),
      );

      final result = await useCase(
        email: 'existing@example.com',
        password: 'secret',
        inviteToken: 'tok123',
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<ServerFailure>()),
        (_) => fail('expected failure'),
      );
    });
  });
}
