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

  group('TreatmentPlanSessionDto — séances persistées relisibles (#7477)',
      () {
    test('fromJson lit id, position, duration_min, status, appointment_id, '
        'quote_item_ids', () {
      final dto = TreatmentPlanSessionDto.fromJson(const {
        'id': 'sess-1',
        'position': 1,
        'duration_min': 30,
        'status': 'scheduled',
        'appointment_id': 'appt-1',
        'quote_item_ids': ['qi-1', 'qi-2'],
      });

      final session = dto.toDomain();
      expect(session.id, 'sess-1');
      expect(session.position, 1);
      expect(session.durationMin, 30);
      expect(session.status, 'scheduled');
      expect(session.appointmentId, 'appt-1');
      expect(session.quoteItemIds, ['qi-1', 'qi-2']);
    });

    test('appointment_id absent → null (séance pas encore programmée)', () {
      final dto = TreatmentPlanSessionDto.fromJson(const {
        'id': 'sess-2',
        'position': 1,
        'duration_min': 30,
        'status': 'planned',
        'quote_item_ids': ['qi-1'],
      });

      expect(dto.toDomain().appointmentId, isNull);
    });
  });

  group('TreatmentPlanDto — sessions absent du JSON (#7477)', () {
    test('plan sans champ sessions → liste vide, pas de crash', () {
      final dto = TreatmentPlanDto.fromJson(const {
        'id': 'plan-1',
        'title': 'Plan implant',
        'status': 'in_progress',
        'created_at': '2026-09-20T00:00:00Z',
      });

      expect(dto.toDomain().sessions, isEmpty);
    });

    test('plan avec sessions → relayées vers le domaine', () {
      final dto = TreatmentPlanDto.fromJson(const {
        'id': 'plan-1',
        'title': 'Plan implant',
        'status': 'in_progress',
        'created_at': '2026-09-20T00:00:00Z',
        'sessions': [
          {
            'id': 'sess-1',
            'position': 1,
            'duration_min': 30,
            'status': 'planned',
            'quote_item_ids': ['qi-1'],
          },
        ],
      });

      final sessions = dto.toDomain().sessions;
      expect(sessions, hasLength(1));
      expect(sessions.single.id, 'sess-1');
    });
  });
}
