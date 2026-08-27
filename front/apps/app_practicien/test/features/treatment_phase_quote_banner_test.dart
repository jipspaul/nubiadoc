//! Tests widget : `PhaseQuoteBanner` (#5019) — bandeau devis en pied de
//! carte de phase, état lié (numéro/signature/acompte) ou état absence.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_practicien/features/treatment_plans/widgets/phase_quote_banner.dart';

void main() {
  Widget buildBanner({
    String? quoteNumber,
    String? signedAtLabel,
    bool depositPaid = false,
    VoidCallback? onOpen,
    VoidCallback? onGenerate,
  }) =>
      MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: PhaseQuoteBanner(
            openKey: const Key('quote_open'),
            generateKey: const Key('quote_generate'),
            quoteNumber: quoteNumber,
            signedAtLabel: signedAtLabel,
            depositPaid: depositPaid,
            onOpen: onOpen ?? () {},
            onGenerate: onGenerate ?? () {},
          ),
        ),
      );

  testWidgets(
      'devis lié → numéro en gras, date de signature, lien Ouvrir, pas d\'acompte',
      (tester) async {
    await tester.pumpWidget(buildBanner(
      quoteNumber: 'DEV-2041',
      signedAtLabel: '04/08',
    ));

    expect(find.textContaining('DEV-2041'), findsOneWidget);
    expect(find.textContaining('signé le 04/08'), findsOneWidget);
    expect(find.textContaining('acompte réglé'), findsNothing);
    expect(find.byIcon(Icons.verified), findsOneWidget);
    expect(find.text('Ouvrir'), findsOneWidget);
    expect(find.byKey(const Key('quote_generate')), findsNothing);
  });

  testWidgets('devis lié + acompte réglé → mention « acompte réglé »',
      (tester) async {
    await tester.pumpWidget(buildBanner(
      quoteNumber: 'DEV-2041',
      signedAtLabel: '04/08',
      depositPaid: true,
    ));

    expect(find.textContaining('acompte réglé'), findsOneWidget);
  });

  testWidgets('devis lié → tap sur Ouvrir déclenche le callback',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(buildBanner(
      quoteNumber: 'DEV-2041',
      signedAtLabel: '04/08',
      onOpen: () => opened = true,
    ));

    await tester.tap(find.byKey(const Key('quote_open')));
    await tester.pumpAndSettle();

    expect(opened, isTrue);
  });

  testWidgets(
      'absence de devis → avertissement ambre, icône error, lien Générer',
      (tester) async {
    await tester.pumpWidget(buildBanner());

    expect(
      find.text("Aucun devis — le patient n'a pas encore accepté cette phase"),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.error), findsOneWidget);
    expect(find.text('Générer'), findsOneWidget);
    expect(find.byKey(const Key('quote_open')), findsNothing);
  });

  testWidgets('absence de devis → tap sur Générer déclenche le callback',
      (tester) async {
    var generated = false;
    await tester.pumpWidget(buildBanner(onGenerate: () => generated = true));

    await tester.tap(find.byKey(const Key('quote_generate')));
    await tester.pumpAndSettle();

    expect(generated, isTrue);
  });
}
