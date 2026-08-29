import 'package:nubia_domain/nubia_domain.dart';
import 'package:test/test.dart';

void main() {
  group('PrescriptionItem.productReference', () {
    const reference = MedicationReference(
      id: 'med-1',
      dci: 'Amoxicilline',
      galenicForm: 'comprimé dispersible',
      therapeuticClass: 'Pénicilline',
    );

    test('null par défaut (rétro-compatibilité lignes historiques)', () {
      const item = PrescriptionItem(
        label: 'Amoxicilline 1g',
        posology: '1 cp matin et soir',
        duration: '7 jours',
        quantity: '1 boîte',
      );

      expect(item.productReference, isNull);
    });

    test('deux lignes avec la même référence produit sont égales', () {
      const a = PrescriptionItem(
        label: 'Amoxicilline 1g',
        productReference: reference,
        posology: '1 cp matin et soir',
        duration: '7 jours',
        quantity: '1 boîte',
      );
      const b = PrescriptionItem(
        label: 'Amoxicilline 1g',
        productReference: reference,
        posology: '1 cp matin et soir',
        duration: '7 jours',
        quantity: '1 boîte',
      );

      expect(a, equals(b));
    });
  });

  group('StructuredPosology.computedQuantity', () {
    test('1 comprimé × 3/j × 5 jours = 15 comprimés', () {
      const posology = StructuredPosology(
        dose: 1,
        frequencyPerDay: 3,
        durationInDays: 5,
      );

      expect(posology.computedQuantity, 15);
    });

    test('deux posologies structurées identiques sont égales', () {
      const a =
          StructuredPosology(dose: 1, frequencyPerDay: 3, durationInDays: 5);
      const b =
          StructuredPosology(dose: 1, frequencyPerDay: 3, durationInDays: 5);

      expect(a, equals(b));
    });

    test('null par défaut sur PrescriptionItem (rétro-compatibilité)', () {
      const item = PrescriptionItem(
        label: 'Amoxicilline 1g',
        posology: '1 cp matin et soir',
        duration: '7 jours',
        quantity: '1 boîte',
      );

      expect(item.structuredPosology, isNull);
    });
  });
}
