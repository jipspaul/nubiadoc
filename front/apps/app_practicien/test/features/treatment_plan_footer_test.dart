//! Tests widget : `PlanFooter` (#5020) — pied de panneau détail d'un plan de
//! traitement (réalisé, engagé, avertissement montant non couvert).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_practicien/features/treatment_plans/widgets/plan_footer.dart';

void main() {
  Widget buildFooter({
    required int realizedCents,
    required int engagedCents,
    required int remainingToQuoteCents,
  }) =>
      MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: PlanFooter(
            key: const Key('plan_footer'),
            warningKey: const Key('plan_footer_warning'),
            realizedCents: realizedCents,
            engagedCents: engagedCents,
            remainingToQuoteCents: remainingToQuoteCents,
          ),
        ),
      );

  testWidgets('affiche réalisé et engagé formatés en NubiaMoney',
      (tester) async {
    await tester.pumpWidget(buildFooter(
      realizedCents: 8242,
      engagedCents: 43592,
      remainingToQuoteCents: 0,
    ));

    expect(
      find.descendant(
        of: find.byKey(const Key('plan_footer')),
        matching: find.textContaining('Réalisé : 82,42 €'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('plan_footer')),
        matching: find.textContaining('Engagé (devis signé) : 435,92 €'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('reste à deviser > 0 → avertissement ambre affiché',
      (tester) async {
    await tester.pumpWidget(buildFooter(
      realizedCents: 8242,
      engagedCents: 43592,
      remainingToQuoteCents: 120000,
    ));

    expect(find.byKey(const Key('plan_footer_warning')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('plan_footer_warning')),
        matching: find.textContaining(
          '1 200,00 € du plan ne sont couverts par aucun devis',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('reste à deviser = 0 → pas d\'avertissement', (tester) async {
    await tester.pumpWidget(buildFooter(
      realizedCents: 8242,
      engagedCents: 43592,
      remainingToQuoteCents: 0,
    ));

    expect(find.byKey(const Key('plan_footer_warning')), findsNothing);
  });
}
