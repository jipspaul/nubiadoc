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
}
