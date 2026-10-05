import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_pharmacie/features/devis/widgets/devis_detail_sheet.dart';

PharmacyQuote _quote({required List<PharmacyQuoteItem> items, int? totalCents}) =>
    PharmacyQuote(
      id: 'q1',
      pharmacyId: 'p1',
      quoteRef: 'DEV-P-0210',
      patientDisplayName: 'Jean D.',
      items: items,
      totalCents: totalCents ??
          items.fold<int>(0, (sum, item) => sum + item.totalCents),
      status: PharmacyQuoteStatus.accepted,
      createdAt: DateTime(2026, 7, 1),
    );

void main() {
  group('DevisDetailSheet — encart remboursement (#8010)', () {
    testWidgets(
        'devis non ventilé (amo/amc nuls) -> encart "Hors remboursement"',
        (tester) async {
      final quote = _quote(items: const [
        PharmacyQuoteItem(
            label: 'Bain de bouche', quantity: 2, unitPriceCents: 450),
      ]);

      await tester.pumpApp(Scaffold(
        body: DevisDetailSheet(quote: quote, onClose: () {}),
      ));

      expect(find.byKey(const Key('devis_sheet_refund_notice')), findsOneWidget);
      expect(
          find.byKey(const Key('devis_sheet_ventilated_notice')), findsNothing);
      expect(find.textContaining('Hors remboursement'), findsOneWidget);
    });

    testWidgets(
        'devis ventilé AMO/AMC (#6897) -> encart reflète la part patient réelle',
        (tester) async {
      // Repro #8010 : qty=2, unit_price_cents=1000 (total ligne 2000),
      // amo_part_cents=800, amc_part_cents=400 -> part patient = 800.
      final quote = _quote(items: const [
        PharmacyQuoteItem(
          label: 'QA-R124 ventile',
          quantity: 2,
          unitPriceCents: 1000,
          amoPartCents: 800,
          amcPartCents: 400,
        ),
      ]);

      await tester.pumpApp(Scaffold(
        body: DevisDetailSheet(quote: quote, onClose: () {}),
      ));

      expect(find.byKey(const Key('devis_sheet_refund_notice')), findsNothing);
      expect(find.byKey(const Key('devis_sheet_ventilated_notice')),
          findsOneWidget);
      expect(find.textContaining('8,00 €'), findsWidgets);
      expect(find.textContaining('4,00 €'), findsOneWidget);
    });
  });
}
