import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_pharmacie/features/orders/widgets/order_wait.dart';

PharmacyOrder _order({
  required PharmacyOrderStatus status,
  required DateTime createdAt,
}) =>
    PharmacyOrder(
      id: 'o1',
      pharmacyId: 'p1',
      patientDisplayName: 'Jean D.',
      prescriptionId: 'rx1',
      status: status,
      createdAt: createdAt,
      updatedAt: createdAt,
    );

void main() {
  final now = DateTime(2026, 8, 13, 11, 21);

  group('orderWaitOf', () {
    test('received depuis 3 h 20 → « Attend 3 h 20 », ton danger', () {
      final order = _order(
        status: PharmacyOrderStatus.received,
        createdAt: DateTime(2026, 8, 13, 8, 1),
      );

      final wait = orderWaitOf(order, now: now);

      expect(wait.label, 'Attend 3 h 20');
      expect(wait.tone, OrderWaitTone.danger);
      expect(wait.isUrgent, isTrue);
    });

    test('preparing depuis 1 h 34 → « Attend 1 h 34 », ton warning', () {
      final order = _order(
        status: PharmacyOrderStatus.preparing,
        createdAt: DateTime(2026, 8, 13, 9, 47),
      );

      final wait = orderWaitOf(order, now: now);

      expect(wait.label, 'Attend 1 h 34');
      expect(wait.tone, OrderWaitTone.warning);
    });

    test('received depuis 1 h 17 (sous le seuil warning) → ton neutral', () {
      final order = _order(
        status: PharmacyOrderStatus.received,
        createdAt: DateTime(2026, 8, 13, 10, 4),
      );

      expect(orderWaitOf(order, now: now).tone, OrderWaitTone.neutral);
    });

    test('preparing depuis moins d\'1 h → « Attend N min »', () {
      final order = _order(
        status: PharmacyOrderStatus.preparing,
        createdAt: DateTime(2026, 8, 13, 10, 23),
      );

      final wait = orderWaitOf(order, now: now);

      expect(wait.label, 'Attend 58 min');
      expect(wait.tone, OrderWaitTone.neutral);
    });

    test('ready depuis 2 h 20 → pas d\'escalade même au-delà du seuil', () {
      final order = _order(
        status: PharmacyOrderStatus.ready,
        createdAt: DateTime(2026, 8, 13, 9, 1),
      );

      final wait = orderWaitOf(order, now: now);

      expect(wait.label, 'Attend 2 h 20');
      expect(wait.tone, OrderWaitTone.neutral);
      expect(wait.isUrgent, isFalse);
    });

    test('minutes paddées à 2 chiffres quand des heures sont affichées', () {
      final order = _order(
        status: PharmacyOrderStatus.received,
        createdAt: DateTime(2026, 8, 13, 9, 19),
      );

      expect(orderWaitOf(order, now: now).label, 'Attend 2 h 02');
    });
  });
}
