import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_core/nubia_core.dart';

void main() {
  group('toothLabelFromFdi', () {
    test('traduit une molaire inférieure gauche (36)', () {
      expect(toothLabelFromFdi('36'), 'Molaire inférieure gauche');
    });

    test('traduit une incisive supérieure droite (11)', () {
      expect(toothLabelFromFdi('11'), 'Incisive supérieure droite');
    });

    test('traduit une canine supérieure gauche (23)', () {
      expect(toothLabelFromFdi('23'), 'Canine supérieure gauche');
    });

    test('traduit une prémolaire inférieure droite (44)', () {
      expect(toothLabelFromFdi('44'), 'Prémolaire inférieure droite');
    });

    test('retourne null pour un code nul', () {
      expect(toothLabelFromFdi(null), isNull);
    });

    test('retourne null pour un code non numérique', () {
      expect(toothLabelFromFdi('abc'), isNull);
    });

    test('retourne null pour un quadrant hors bornes (0X, 5X)', () {
      expect(toothLabelFromFdi('06'), isNull);
      expect(toothLabelFromFdi('56'), isNull);
    });

    test('retourne null pour une position hors bornes (X0, X9)', () {
      expect(toothLabelFromFdi('10'), isNull);
      expect(toothLabelFromFdi('19'), isNull);
    });
  });
}
