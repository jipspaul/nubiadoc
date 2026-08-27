import 'package:flutter_test/flutter_test.dart';

import 'package:app_practicien/features/lab_work/lab_work_order_due.dart';

void main() {
  final now = DateTime.parse('2026-08-26T09:00:00Z'); // mercredi

  group('labWorkOrderDueOf', () {
    test('sans date attendue → null, pas de crash', () {
      final due = labWorkOrderDueOf(
        status: 'sent',
        expectedReturnAt: null,
        now: now,
      );

      expect(due, isNull);
    });

    test('bon "fitted" → null même avec une date dépassée', () {
      final due = labWorkOrderDueOf(
        status: 'fitted',
        expectedReturnAt: '2026-08-01T09:00:00Z',
        now: now,
      );

      expect(due, isNull);
    });

    test('date dépassée de 6 j → « Retard de 6 j », ton overdue', () {
      final due = labWorkOrderDueOf(
        status: 'sent',
        expectedReturnAt: '2026-08-20T09:00:00Z',
        now: now,
      );

      expect(due?.label, 'Retard de 6 j');
      expect(due?.tone, LabWorkOrderDueTone.overdue);
    });

    test('date dépassée le jour même (heure passée) → au moins 1 j de retard',
        () {
      final due = labWorkOrderDueOf(
        status: 'try_in',
        expectedReturnAt: '2026-08-26T05:00:00Z',
        now: now,
      );

      expect(due?.label, 'Retard de 1 j');
      expect(due?.tone, LabWorkOrderDueTone.overdue);
    });

    test("date attendue aujourd'hui (heure à venir) → « Attendu aujourd'hui »",
        () {
      final due = labWorkOrderDueOf(
        status: 'sent',
        expectedReturnAt: '2026-08-26T18:00:00Z',
        now: now,
      );

      expect(due?.label, "Attendu aujourd'hui");
      expect(due?.tone, LabWorkOrderDueTone.soon);
    });

    test('date attendue dans 2 j → « Attendu vendredi », ton soon', () {
      final due = labWorkOrderDueOf(
        status: 'sent',
        expectedReturnAt: '2026-08-28T09:00:00Z',
        now: now,
      );

      expect(due?.label, 'Attendu vendredi');
      expect(due?.tone, LabWorkOrderDueTone.soon);
    });

    test('date attendue au-delà de 7 j → « Attendu le JJ/MM », ton onTime',
        () {
      final due = labWorkOrderDueOf(
        status: 'sent',
        expectedReturnAt: '2026-09-10T09:00:00Z',
        now: now,
      );

      expect(due?.label, 'Attendu le 10/09');
      expect(due?.tone, LabWorkOrderDueTone.onTime);
    });
  });
}
