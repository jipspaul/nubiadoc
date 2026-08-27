import 'package:flutter_test/flutter_test.dart';

import 'package:nubia_data/src/remote/treatment_plans/treatment_plans_dto.dart';

void main() {
  group('TreatmentPhaseActDto — parsing tolérant (#5012)', () {
    test('fromJson lit label, ccam_code, tooth, amount_cents, subtitle', () {
      final dto = TreatmentPhaseActDto.fromJson(const {
        'id': 'act-1',
        'label': 'Détartrage complet',
        'ccam_code': 'HBJD001',
        'tooth': '26',
        'amount_cents': 2892,
        'subtitle': 'Réalisé le 22/07',
      });

      expect(dto.toDomain().label, 'Détartrage complet');
      expect(dto.toDomain().ccamCode, 'HBJD001');
      expect(dto.toDomain().tooth, '26');
      expect(dto.toDomain().amountCents, 2892);
      expect(dto.toDomain().subtitle, 'Réalisé le 22/07');
    });

    test('fromJson sur un objet minimal → valeurs neutres, pas de crash', () {
      final dto = TreatmentPhaseActDto.fromJson(const {
        'id': 'act-2',
        'amount_cents': 120000,
      });

      final act = dto.toDomain();
      expect(act.label, '');
      expect(act.ccamCode, isNull);
      expect(act.tooth, isNull);
      expect(act.amountCents, 120000);
      expect(act.subtitle, isNull);
    });
  });

  group('TreatmentPhaseDto — acts absent du JSON (#5012)', () {
    test('phase sans champ acts → liste vide, pas de crash', () {
      final dto = TreatmentPhaseDto.fromJson(const {
        'id': 'phase-1',
        'position': 1,
        'title': 'Assainissement',
        'status': 'done',
      });

      expect(dto.toDomain().acts, isEmpty);
    });
  });
}
