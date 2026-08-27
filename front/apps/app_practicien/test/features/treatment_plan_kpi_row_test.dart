//! Tests widget : `PlanKpiRow` (#5017) — trois KPIs de l'en-tête de panneau
//! détail d'un plan de traitement (total / devis signé / reste à deviser).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_practicien/features/treatment_plans/widgets/plan_kpi_row.dart';

void main() {
  Widget buildRow({
    required int totalCents,
    required int signedCents,
    required int remainingToQuoteCents,
  }) =>
      MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: PlanKpiRow(
            totalCents: totalCents,
            signedCents: signedCents,
            remainingToQuoteCents: remainingToQuoteCents,
          ),
        ),
      );

  testWidgets('affiche les trois libellés en capitales', (tester) async {
    await tester.pumpWidget(buildRow(
      totalCents: 163592,
      signedCents: 43592,
      remainingToQuoteCents: 120000,
    ));

    expect(find.text('TOTAL DU PLAN'), findsOneWidget);
    expect(find.text('DEVIS SIGNÉ'), findsOneWidget);
    expect(find.text('RESTE À DEVISER'), findsOneWidget);
  });

  testWidgets('montants formatés NubiaMoney.formatCents', (tester) async {
    await tester.pumpWidget(buildRow(
      totalCents: 163592,
      signedCents: 43592,
      remainingToQuoteCents: 120000,
    ));

    expect(
      find.descendant(
        of: find.byKey(const Key('plan_kpi_total')),
        matching: find.text('1 635,92 €'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('plan_kpi_signed')),
        matching: find.text('435,92 €'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('plan_kpi_remaining')),
        matching: find.text('1 200,00 €'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('« Total du plan » plus grand que les deux autres KPIs',
      (tester) async {
    await tester.pumpWidget(buildRow(
      totalCents: 163592,
      signedCents: 43592,
      remainingToQuoteCents: 120000,
    ));

    Text amountOf(Key key) => tester.widget<Text>(
          find
              .descendant(
                of: find.byKey(key),
                matching: find.byType(Text),
              )
              .last,
        );

    final totalStyle = amountOf(const Key('plan_kpi_total')).style;
    final signedStyle = amountOf(const Key('plan_kpi_signed')).style;
    final remainingStyle = amountOf(const Key('plan_kpi_remaining')).style;

    expect(totalStyle!.fontSize! > signedStyle!.fontSize!, isTrue);
    expect(totalStyle.fontSize! > remainingStyle!.fontSize!, isTrue);
  });
}
