import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/nubia_data.dart';
import 'package:nubia_domain/nubia_domain.dart';

void main() {
  group('PrescriptionItemDto.structuredPosology (#4993)', () {
    test('absent → null, pas de crash (rétro-compatibilité)', () {
      final item = PrescriptionItemDto.fromJson({
        'label': 'Amoxicilline 1g',
        'posology': '1 cp matin et soir',
        'duration': '7 jours',
        'quantity': '1 boîte',
      }).toDomain();

      expect(item.structuredPosology, isNull);
    });

    test('présent → aller-retour JSON fidèle', () {
      final dto = PrescriptionItemDto.fromJson({
        'label': 'Amoxicilline 1g',
        'posology': '1 cp matin et soir',
        'duration': '5 jours',
        'quantity': '15 comprimés',
        'structured_posology': {
          'dose': 1,
          'frequency_per_day': 3,
          'duration_in_days': 5,
        },
      });
      final item = dto.toDomain();

      expect(item.structuredPosology, isNotNull);
      expect(item.structuredPosology!.dose, 1);
      expect(item.structuredPosology!.frequencyPerDay, 3);
      expect(item.structuredPosology!.durationInDays, 5);
      expect(item.structuredPosology!.computedQuantity, 15);

      final roundTripped = PrescriptionItemDto.fromDomain(item).toJson();
      expect(roundTripped['structured_posology'], {
        'dose': 1.0,
        'frequency_per_day': 3.0,
        'duration_in_days': 5,
      });
    });

    test(
        '#6156 : ligne historique divergente (champs renommés, dose string) '
        '→ null, pas de TypeError', () {
      final item = PrescriptionItemDto.fromJson({
        'label': 'Amoxicilline 1g',
        'posology': '1 cp matin et soir',
        'duration': '7 jours',
        'quantity': '1 boîte',
        'structured_posology': {
          'dose': '1g',
          'duration_days': 7,
          'frequency': '2x/jour',
        },
      }).toDomain();

      expect(item.structuredPosology, isNull);
    });

    test('#6156 : dose non numérique dans le schéma attendu → null', () {
      final item = PrescriptionItemDto.fromJson({
        'label': 'Amoxicilline 1g',
        'posology': '1 cp matin et soir',
        'duration': '7 jours',
        'quantity': '1 boîte',
        'structured_posology': {
          'dose': 'totally-not-a-number',
          'frequency_per_day': 2,
          'duration_in_days': 7,
        },
      }).toDomain();

      expect(item.structuredPosology, isNull);
    });

    test('fromDomain sans posologie structurée → clé absente du JSON', () {
      const item = PrescriptionItem(
        label: 'Doliprane',
        posology: 'si douleur',
        duration: '',
        quantity: '8 cp',
      );

      final json = PrescriptionItemDto.fromDomain(item).toJson();

      expect(json.containsKey('structured_posology'), isFalse);
    });
  });
}
