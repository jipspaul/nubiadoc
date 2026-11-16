// #8637 — une entrée historique peut avoir firstName/lastName tous deux
// vides (chemins de création désormais gardés par un 422 côté API, mais la
// donnée existe déjà en base) ; sans repli, `'$firstName $lastName'` rend
// une simple espace, invisible à l'écran comme dans l'arbre Semantics.
import 'package:nubia_domain/nubia_domain.dart';
import 'package:test/test.dart';

void main() {
  group('Dependent.displayName', () {
    test('concatène prénom et nom quand les deux sont renseignés', () {
      const dependent = Dependent(
        id: 'dep-1',
        firstName: 'Lucas',
        lastName: 'Marchand',
        relationship: DependentRelationship.enfant,
      );

      expect(dependent.displayName, 'Lucas Marchand');
    });

    test('retombe sur "Sans nom" si les deux noms sont vides', () {
      const dependent = Dependent(
        id: 'dep-2',
        firstName: '',
        lastName: '',
        relationship: DependentRelationship.conjoint,
      );

      expect(dependent.displayName, 'Sans nom');
    });

    test('retombe sur "Sans nom" si les deux noms ne contiennent que des '
        'espaces', () {
      const dependent = Dependent(
        id: 'dep-3',
        firstName: '   ',
        lastName: '  ',
        relationship: DependentRelationship.conjoint,
      );

      expect(dependent.displayName, 'Sans nom');
    });
  });
}
