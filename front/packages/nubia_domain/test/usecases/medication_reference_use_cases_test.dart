import 'package:dartz/dartz.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:test/test.dart';

class MockMedicationReferenceRepository extends Mock
    implements MedicationReferenceRepository {}

void main() {
  const reference = MedicationReference(
    id: 'med-1',
    dci: 'Amoxicilline',
    galenicForm: 'comprimé dispersible',
    therapeuticClass: 'Pénicilline',
  );

  group('SearchMedicationReferencesUseCase', () {
    late MockMedicationReferenceRepository repo;

    setUp(() => repo = MockMedicationReferenceRepository());

    test('délègue la recherche au repository', () async {
      when(() => repo.searchMedicationReferences(query: 'amox'))
          .thenAnswer((_) async => const Right([reference]));

      final result =
          await SearchMedicationReferencesUseCase(repo)(query: 'amox');

      expect(result.getOrElse(() => []), [reference]);
      verify(() => repo.searchMedicationReferences(query: 'amox')).called(1);
    });

    test('propage le Failure du repo', () async {
      when(() => repo.searchMedicationReferences(query: 'xx')).thenAnswer(
        (_) async => const Left(
          ServerFailure(message: 'Référentiel indisponible.', statusCode: 503),
        ),
      );

      final result =
          await SearchMedicationReferencesUseCase(repo)(query: 'xx');

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect((failure as ServerFailure).statusCode, 503),
        (_) => fail('expected Left'),
      );
    });
  });
}
