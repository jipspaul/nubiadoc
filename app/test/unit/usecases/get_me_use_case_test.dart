import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';
import 'package:nubia_patient/domain/repositories/auth_repository.dart';
import 'package:nubia_patient/domain/usecases/auth/get_me_use_case.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

PatientAccount _makeAccount() => const PatientAccount(
      id: 'u1',
      firstName: 'Camille',
      lastName: 'Dupont',
      email: 'camille@example.com',
    );

void main() {
  late MockAuthRepository repository;
  late GetMeUseCase useCase;

  setUp(() {
    repository = MockAuthRepository();
    useCase = GetMeUseCase(repository);
  });

  group('GetMeUseCase', () {
    test('returns PatientAccount on success', () async {
      final account = _makeAccount();
      when(() => repository.getMe()).thenAnswer((_) async => Right(account));

      final result = await useCase();

      expect(result, Right<Failure, PatientAccount>(account));
      verify(() => repository.getMe()).called(1);
    });

    test('returns NetworkFailure on network error', () async {
      when(() => repository.getMe())
          .thenAnswer((_) async => const Left(NetworkFailure()));

      final result = await useCase();

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<NetworkFailure>()),
        (_) => fail('expected failure'),
      );
    });
  });
}
