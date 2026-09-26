import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

void main() {
  group('pluralize (#6982)', () {
    test('accorde au singulier pour 0', () {
      expect(pluralize(0, 'restant'), 'restant');
    });

    test('accorde au singulier pour 1', () {
      expect(pluralize(1, 'restant'), 'restant');
    });

    test('accorde au pluriel au-delà de 1', () {
      expect(pluralize(2, 'restant'), 'restants');
      expect(pluralize(8, 'restant'), 'restants');
    });

    test('utilise le pluriel irrégulier fourni quand présent', () {
      expect(pluralize(1, 'étape'), 'étape');
      expect(pluralize(3, 'étape'), 'étapes');
    });
  });
}
