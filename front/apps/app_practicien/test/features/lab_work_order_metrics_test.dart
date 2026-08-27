import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/lab_work/lab_work_order_metrics.dart';

const _now = '2026-08-26T09:00:00Z';

LabWorkOrder _order({
  required String id,
  required String status,
  required int purchasePriceCents,
  String? expectedReturnAt,
}) =>
    LabWorkOrder(
      id: id,
      patientId: 'patient-$id',
      patientDisplayName: 'Patient $id',
      toothFdi: '11',
      workNature: 'Couronne',
      labName: 'Labo $id',
      purchasePriceCents: purchasePriceCents,
      status: status,
      sentAt: '2026-08-01T09:00:00Z',
      expectedReturnAt: expectedReturnAt,
    );

void main() {
  group('computeLabWorkOrderMetrics', () {
    test('compte les bons non "fitted" comme en cours', () {
      final orders = [
        _order(id: '1', status: 'sent', purchasePriceCents: 10000),
        _order(id: '2', status: 'try_in', purchasePriceCents: 20000),
        _order(id: '3', status: 'fitted', purchasePriceCents: 30000),
      ];

      final metrics =
          computeLabWorkOrderMetrics(orders, now: DateTime.parse(_now));

      expect(metrics.inProgressCount, 2);
    });

    test('un bon en cours avec une date de retour dépassée est en retard', () {
      final orders = [
        _order(
          id: '1',
          status: 'sent',
          purchasePriceCents: 10000,
          expectedReturnAt: '2026-08-20T09:00:00Z',
        ),
      ];

      final metrics =
          computeLabWorkOrderMetrics(orders, now: DateTime.parse(_now));

      expect(metrics.overdueCount, 1);
      expect(metrics.dueThisWeekCount, 0);
    });

    test(
        'un bon en cours attendu dans les 7 jours compte dans "cette '
        'semaine", pas en retard', () {
      final orders = [
        _order(
          id: '1',
          status: 'sent',
          purchasePriceCents: 10000,
          expectedReturnAt: '2026-08-30T09:00:00Z',
        ),
      ];

      final metrics =
          computeLabWorkOrderMetrics(orders, now: DateTime.parse(_now));

      expect(metrics.dueThisWeekCount, 1);
      expect(metrics.overdueCount, 0);
    });

    test('un bon attendu au-delà de 7 jours ne compte dans aucun des deux', () {
      final orders = [
        _order(
          id: '1',
          status: 'sent',
          purchasePriceCents: 10000,
          expectedReturnAt: '2026-09-15T09:00:00Z',
        ),
      ];

      final metrics =
          computeLabWorkOrderMetrics(orders, now: DateTime.parse(_now));

      expect(metrics.dueThisWeekCount, 0);
      expect(metrics.overdueCount, 0);
    });

    test('un bon "fitted" en retard ne compte ni en retard ni cette semaine',
        () {
      final orders = [
        _order(
          id: '1',
          status: 'fitted',
          purchasePriceCents: 10000,
          expectedReturnAt: '2026-08-01T09:00:00Z',
        ),
      ];

      final metrics =
          computeLabWorkOrderMetrics(orders, now: DateTime.parse(_now));

      expect(metrics.overdueCount, 0);
      expect(metrics.dueThisWeekCount, 0);
    });

    test(
        'le montant engagé somme les prix d\'achat des bons en cours '
        'uniquement', () {
      final orders = [
        _order(id: '1', status: 'sent', purchasePriceCents: 150000),
        _order(id: '2', status: 'try_in', purchasePriceCents: 200000),
        _order(id: '3', status: 'fitted', purchasePriceCents: 999999),
      ];

      final metrics =
          computeLabWorkOrderMetrics(orders, now: DateTime.parse(_now));

      expect(metrics.committedCents, 350000);
    });

    test('liste vide → tous les agrégats à zéro', () {
      final metrics = computeLabWorkOrderMetrics([], now: DateTime.parse(_now));

      expect(metrics.inProgressCount, 0);
      expect(metrics.overdueCount, 0);
      expect(metrics.dueThisWeekCount, 0);
      expect(metrics.committedCents, 0);
    });
  });
}
