import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/nubia_data.dart';

void main() {
  group('CabinetPayoutDto', () {
    // Régression #5968 : `_probableLead()` côté front dépend de
    // `payout.internalPayments` (liste détaillée), mais le test widget
    // historique construisait l'entité `CabinetPayout` à la main plutôt que
    // de décoder un vrai payload API, donc il ne pouvait jamais détecter que
    // le DTO ne mappait pas `internal_payments` — l'encart « Piste probable »
    // ne s'affichait jamais en production malgré des tests verts. Ce test
    // décode un payload au format réel `GET /v1/cabinet/payouts`
    // (`api/src/cabinet_payouts.rs`, `PayoutView`/`InternalPaymentView`) pour
    // que tout renommage/suppression du champ côté back fasse échouer ce
    // test plutôt que de rester silencieusement invisible.
    test(
        'fromJson().toDomain() mappe internal_payments (liste détaillée) '
        'depuis un payload API réel', () {
      final dto = CabinetPayoutDto.fromJson({
        'id': 'po_mock_cash_lead',
        'provider': 'stripe',
        'amount_cents': 184200,
        'currency': 'EUR',
        'arrival_date': '2026-08-08',
        'provider_status': 'paid',
        'reconciliation_status': 'to_verify',
        'internal_payments_total_cents': 202400,
        'internal_payments': [
          {
            'patient_name': 'Camille Moreau',
            'time': '14:32',
            'amount_cents': 72500,
            'method_label': 'Carte',
            'reconcilable_by_provider': true,
          },
          {
            'patient_name': 'Léa Bernard',
            'time': '10:02',
            'amount_cents': 18200,
            'method_label': 'Espèces',
            'reconcilable_by_provider': false,
          },
        ],
      });

      final domain = dto.toDomain();
      expect(domain.internalPayments, hasLength(2));
      expect(domain.internalPayments.first.patientName, 'Camille Moreau');
      expect(domain.internalPayments.first.amountCents, 72500);
      expect(domain.internalPayments.last.reconcilableByProvider, isFalse);

      // La « piste probable » : paiement non rapprochable par le
      // prestataire dont le montant égale exactement l'écart
      // (`differenceCents`) — c'est ce que `_probableLead()` recherche.
      final lead = domain.internalPayments.firstWhere(
        (p) =>
            !p.reconcilableByProvider &&
            p.amountCents == domain.differenceCents.abs(),
      );
      expect(lead.patientName, 'Léa Bernard');
    });

    test(
        'fromJson tolère internal_payments absent (ancien payload) sans '
        'crasher, liste vide', () {
      final dto = CabinetPayoutDto.fromJson({
        'id': 'po_mock_unmatched',
        'provider': 'stripe',
        'amount_cents': 999999,
        'currency': 'EUR',
        'arrival_date': '2026-07-30',
        'provider_status': 'paid',
        'reconciliation_status': 'to_verify',
        'internal_payments_total_cents': 0,
      });

      expect(dto.toDomain().internalPayments, isEmpty);
    });
  });
}
