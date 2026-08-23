import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

void main() {
  group('initialsFrom', () {
    test('prénom + nom → initiale de chacun (#5163)', () {
      expect(initialsFrom('Marc Dubois'), 'MD');
      expect(initialsFrom('Théo Girard'), 'TG');
    });

    test('un seul mot → deux premières lettres', () {
      expect(initialsFrom('Léa'), 'LÉ');
    });

    test('nom vide → repli non vide', () {
      expect(initialsFrom(''), isNotEmpty);
      expect(initialsFrom('   '), isNotEmpty);
    });
  });
}
