// #5230 — DependentRelationship distingue enfant/conjoint/autre mais la
// bascule de majorité ne concerne que l'enfant : à 18 ans, l'accès du
// parent au dossier de son enfant doit cesser. Le mécanisme est pur/
// paramétré par une date de référence pour rester testable sans horloge.
import 'package:nubia_domain/nubia_domain.dart';
import 'package:test/test.dart';

void main() {
  group('Dependent — âge et bascule de majorité', () {
    test('ageInYearsAt est null sans date de naissance', () {
      const dependent = Dependent(
        id: 'dep-1',
        firstName: 'Lucas',
        lastName: 'Marchand',
        relationship: DependentRelationship.enfant,
      );

      expect(dependent.ageInYearsAt(DateTime(2026, 1, 1)), isNull);
      expect(dependent.hasParentalAccessExpiredAt(DateTime(2026, 1, 1)), isFalse);
    });

    test('ageInYearsAt compte les années révolues (anniversaire pas encore passé)',
        () {
      final dependent = Dependent(
        id: 'dep-1',
        firstName: 'Lucas',
        lastName: 'Marchand',
        dateOfBirth: DateTime(2015, 8, 25),
        relationship: DependentRelationship.enfant,
      );

      expect(dependent.ageInYearsAt(DateTime(2026, 8, 24)), 10);
      expect(dependent.ageInYearsAt(DateTime(2026, 8, 25)), 11);
    });

    test('un enfant de moins de 18 ans ne déclenche pas la bascule', () {
      final dependent = Dependent(
        id: 'dep-1',
        firstName: 'Lucas',
        lastName: 'Marchand',
        dateOfBirth: DateTime(2015, 8, 25),
        relationship: DependentRelationship.enfant,
      );

      expect(dependent.hasParentalAccessExpiredAt(DateTime(2026, 8, 25)), isFalse);
    });

    test("l'accès du parent expire le jour des 18 ans de l'enfant", () {
      final dependent = Dependent(
        id: 'dep-1',
        firstName: 'Lucas',
        lastName: 'Marchand',
        dateOfBirth: DateTime(2008, 8, 25),
        relationship: DependentRelationship.enfant,
      );

      expect(dependent.hasParentalAccessExpiredAt(DateTime(2026, 8, 24)), isFalse);
      expect(dependent.hasParentalAccessExpiredAt(DateTime(2026, 8, 25)), isTrue);
    });

    test('un conjoint ou un autre proche ne sont jamais concernés par la bascule',
        () {
      final spouse = Dependent(
        id: 'dep-2',
        firstName: 'Émile',
        lastName: 'Martin',
        dateOfBirth: DateTime(1980, 1, 1),
        relationship: DependentRelationship.conjoint,
      );
      final other = Dependent(
        id: 'dep-3',
        firstName: 'Alan',
        lastName: 'Santé',
        dateOfBirth: DateTime(1970, 1, 1),
        relationship: DependentRelationship.autre,
      );

      expect(spouse.hasParentalAccessExpiredAt(DateTime(2026, 1, 1)), isFalse);
      expect(other.hasParentalAccessExpiredAt(DateTime(2026, 1, 1)), isFalse);
    });
  });
}
