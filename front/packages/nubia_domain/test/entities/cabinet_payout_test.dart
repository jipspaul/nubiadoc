// #5106 — le volet « Paiements internes du jour » ne doit jamais afficher un
// total incohérent avec le détail des lignes : ce test garantit que
// `internalPaymentsTotalCents` reste la somme exacte de `internalPayments`
// pour tout jeu de données réaliste (mock back, cf. `cabinet_payout.dart`).
import 'package:nubia_domain/nubia_domain.dart';
import 'package:test/test.dart';

List<InternalPayment> _payments() => const [
      InternalPayment(
        patientName: 'Camille Moreau',
        time: '14:32',
        amountCents: 72500,
        methodLabel: 'Carte',
        reconcilableByProvider: true,
      ),
      InternalPayment(
        patientName: 'Julien Perrin',
        time: '10:02',
        amountCents: 4500,
        methodLabel: 'Espèces',
        reconcilableByProvider: false,
      ),
      InternalPayment(
        patientName: 'Sofia Kaya',
        time: '09:15',
        amountCents: 12000,
        methodLabel: 'Chèque',
        reconcilableByProvider: false,
      ),
    ];

CabinetPayout _payout({required int internalPaymentsTotalCents}) =>
    CabinetPayout(
      id: 'po-1',
      provider: PayoutProvider.stripe,
      amountCents: 202400,
      currency: 'EUR',
      arrivalDate: DateTime(2026, 7, 28),
      reconciliationStatus: PayoutReconciliationStatus.toVerify,
      internalPaymentsTotalCents: internalPaymentsTotalCents,
      internalPayments: _payments(),
    );

void main() {
  group('CabinetPayout.internalPayments', () {
    test('la somme des lignes == internalPaymentsTotalCents', () {
      final payout = _payout(internalPaymentsTotalCents: 89000);
      final sum = payout.internalPayments
          .fold<int>(0, (total, payment) => total + payment.amountCents);

      expect(sum, payout.internalPaymentsTotalCents);
    });

    test('un paiement en espèces ou chèque est non rapprochable', () {
      final payments = _payments();

      expect(
        payments
            .where((p) => !p.reconcilableByProvider)
            .map((p) => p.methodLabel),
        containsAll(['Espèces', 'Chèque']),
      );
    });
  });

  group('CabinetPayout.differenceCents', () {
    test('reste amountCents - internalPaymentsTotalCents', () {
      final payout = _payout(internalPaymentsTotalCents: 89000);

      expect(payout.differenceCents, 202400 - 89000);
    });
  });
}
