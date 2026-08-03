//! Tests : libellés anatomiques FDI (module dentaire, refonte lot 3).

import 'package:flutter_test/flutter_test.dart';

import 'package:app_practicien/features/consultation_clinique/modules/dentaire/tooth_anatomy_labels.dart';

void main() {
  test('dents permanentes : rang et quadrant', () {
    expect(toothAnatomyLabel('26'), '1ère molaire · maxillaire G');
    expect(toothAnatomyLabel('11'), 'incisive centrale · maxillaire D');
    expect(toothAnatomyLabel('33'), 'canine · mandibule G');
    expect(toothAnatomyLabel('48'), 'dent de sagesse · mandibule D');
  });

  test('denture lactéale : suffixe (lait), 5 dents par quadrant', () {
    expect(toothAnatomyLabel('55'), '2e molaire · maxillaire D (lait)');
    expect(toothAnatomyLabel('61'), 'incisive centrale · maxillaire G (lait)');
    // Rang 6 inexistant en denture lait.
    expect(toothAnatomyLabel('56'), isNull);
  });

  test('codes invalides → null', () {
    expect(toothAnatomyLabel('9'), isNull);
    expect(toothAnatomyLabel('99'), isNull);
    expect(toothAnatomyLabel('065'), isNull);
    expect(toothAnatomyLabel('zz'), isNull);
    expect(toothAnatomyLabel(''), isNull);
  });
}
