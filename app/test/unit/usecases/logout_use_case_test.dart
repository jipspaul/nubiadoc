import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/repositories/auth_repository.dart';
import 'package:nubia_patient/domain/usecases/auth/logout_use_case.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository repository;
  late LogoutUseCase useCase;

  setUp(() {
    repository = MockAuthRepository();
    useCase = LogoutUseCase(repository);
  });

  group('LogoutUseCase', () {
    test('clears tokens and returns Right on success', () async {
      when(() => repository.logout())
          .thenAnswer((_) async => const Right(null));

      final result = await useCase();

      expect(result.isRight(), isTrue);
      verify(() => repository.logout()).called(1);
    });

    test('returns Failure when repository fails', () async {
      when(() => repository.logout())
          .thenAnswer((_) async => const Left(NetworkFailure()));

      final result = await useCase();

      expect(result.isLeft(), isTrue);
    });
  });
}
