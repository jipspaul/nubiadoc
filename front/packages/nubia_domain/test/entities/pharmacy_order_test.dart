import 'package:nubia_domain/nubia_domain.dart';
import 'package:test/test.dart';

void main() {
  group('PharmacyOrderStatus.canTransitionTo', () {
    test('received → preparing, rejected, cancelled autorisés', () {
      expect(
        PharmacyOrderStatus.received
            .canTransitionTo(PharmacyOrderStatus.preparing),
        isTrue,
      );
      expect(
        PharmacyOrderStatus.received
            .canTransitionTo(PharmacyOrderStatus.rejected),
        isTrue,
      );
      expect(
        PharmacyOrderStatus.received
            .canTransitionTo(PharmacyOrderStatus.cancelled),
        isTrue,
      );
    });

    test('received → ready ou pickedUp interdits (pas de saut d\'étape)', () {
      expect(
        PharmacyOrderStatus.received.canTransitionTo(PharmacyOrderStatus.ready),
        isFalse,
      );
      expect(
        PharmacyOrderStatus.received
            .canTransitionTo(PharmacyOrderStatus.pickedUp),
        isFalse,
      );
    });

    test('preparing → ready et cancelled autorisés, rejected interdit', () {
      expect(
        PharmacyOrderStatus.preparing
            .canTransitionTo(PharmacyOrderStatus.ready),
        isTrue,
      );
      expect(
        PharmacyOrderStatus.preparing
            .canTransitionTo(PharmacyOrderStatus.cancelled),
        isTrue,
      );
      expect(
        PharmacyOrderStatus.preparing
            .canTransitionTo(PharmacyOrderStatus.rejected),
        isFalse,
      );
    });

    test('ready → pickedUp seul autorisé (plus d\'annulation possible)', () {
      expect(
        PharmacyOrderStatus.ready.canTransitionTo(PharmacyOrderStatus.pickedUp),
        isTrue,
      );
      expect(
        PharmacyOrderStatus.ready
            .canTransitionTo(PharmacyOrderStatus.cancelled),
        isFalse,
      );
      expect(
        PharmacyOrderStatus.ready
            .canTransitionTo(PharmacyOrderStatus.preparing),
        isFalse,
      );
    });

    test('états terminaux : aucune transition sortante', () {
      for (final terminal in [
        PharmacyOrderStatus.pickedUp,
        PharmacyOrderStatus.rejected,
        PharmacyOrderStatus.cancelled,
      ]) {
        for (final next in PharmacyOrderStatus.values) {
          expect(
            terminal.canTransitionTo(next),
            isFalse,
            reason: '$terminal → $next devrait être interdit',
          );
        }
        expect(terminal.isTerminal, isTrue);
      }
    });
  });

  group('PharmacyOrder', () {
    PharmacyOrder makeOrder(PharmacyOrderStatus status) => PharmacyOrder(
          id: 'o1',
          pharmacyId: 'p1',
          prescriptionId: 'rx1',
          status: status,
          createdAt: DateTime.utc(2026, 7, 1),
          updatedAt: DateTime.utc(2026, 7, 2),
        );

    test('canShowPickupCode uniquement quand ready', () {
      for (final status in PharmacyOrderStatus.values) {
        expect(
          makeOrder(status).canShowPickupCode,
          status == PharmacyOrderStatus.ready,
          reason: 'statut $status',
        );
      }
    });

    test('égalité Equatable sur id + status + updatedAt', () {
      expect(
        makeOrder(PharmacyOrderStatus.received),
        equals(makeOrder(PharmacyOrderStatus.received)),
      );
      expect(
        makeOrder(PharmacyOrderStatus.received),
        isNot(equals(makeOrder(PharmacyOrderStatus.preparing))),
      );
    });

    test('hasBillingSummary uniquement si les 4 montants sont renseignés '
        '(#4888)', () {
      expect(makeOrder(PharmacyOrderStatus.received).hasBillingSummary,
          isFalse);

      final billed = PharmacyOrder(
        id: 'o1',
        pharmacyId: 'p1',
        prescriptionId: 'rx1',
        status: PharmacyOrderStatus.ready,
        createdAt: DateTime.utc(2026, 7, 1),
        updatedAt: DateTime.utc(2026, 7, 2),
        billingTotalCents: 2480,
        billingAmoShareCents: 1636,
        billingAmcShareCents: 644,
        billingPatientShareCents: 200,
      );
      expect(billed.hasBillingSummary, isTrue);
    });
  });

  group('PharmacyQuote', () {
    test('isDecidable uniquement quand sent', () {
      PharmacyQuote makeQuote(PharmacyQuoteStatus status) => PharmacyQuote(
            id: 'q1',
            pharmacyId: 'p1',
            items: const [],
            totalCents: 1250,
            status: status,
            createdAt: DateTime.utc(2026, 7, 1),
          );
      for (final status in PharmacyQuoteStatus.values) {
        expect(
          makeQuote(status).isDecidable,
          status == PharmacyQuoteStatus.sent,
        );
      }
    });

    test('PharmacyQuoteItem.totalCents = quantité × prix unitaire', () {
      const item = PharmacyQuoteItem(
          label: 'Bain de bouche', quantity: 3, unitPriceCents: 450);
      expect(item.totalCents, 1350);
    });
  });

  group('Pharmacy', () {
    test('distanceKm dérivé de distanceM', () {
      const pharmacy =
          Pharmacy(id: 'p1', name: 'Pharmacie du Port', distanceM: 1500);
      expect(pharmacy.distanceKm, 1.5);
      const noGeo = Pharmacy(id: 'p2', name: 'Sans géo');
      expect(noGeo.distanceKm, isNull);
    });
  });
}
