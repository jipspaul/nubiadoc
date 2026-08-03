//! Tests widget : écran de clôture enrichi (refonte consultation, lot 4 —
//! devis transmis, décompte de séances #4120, enchaînements agenda).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/widgets/consultation_completed_view.dart';

void main() {
  Future<GoRouter> pump(WidgetTester tester,
      {SessionCompleteResult? result}) async {
    final router = GoRouter(
      initialLocation: '/done',
      routes: [
        GoRoute(
          path: '/done',
          builder: (_, __) =>
              Scaffold(body: ConsultationCompletedView(result: result)),
        ),
        GoRoute(
          path: '/agenda',
          builder: (_, __) => const Scaffold(body: Text('agenda-page')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(
      theme: NubiaTheme.light,
      routerConfig: router,
    ));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('avec devis + séances restantes : badge et deux enchaînements',
      (tester) async {
    await pump(tester,
        result: const SessionCompleteResult(
          invoiceId: 'inv-1',
          nextStep: 'quote_sent',
          sessionsRemaining: 2,
        ));

    expect(find.byKey(const Key('consultation_completed')), findsOneWidget);
    expect(
      tester
          .widget<Text>(
              find.byKey(const Key('consultation_completed_subtitle')))
          .data,
      contains('devis'),
    );
    expect(find.byKey(const Key('sessions_remaining_badge')), findsOneWidget);
    expect(find.textContaining('2 séance(s) restante(s)'), findsOneWidget);
    expect(find.byKey(const Key('completed_schedule_next')), findsOneWidget);
  });

  testWidgets(
      'phase épuisée : badge « Phase terminée », pas de re-programmation',
      (tester) async {
    await pump(tester,
        result: const SessionCompleteResult(sessionsRemaining: 0));

    expect(find.text('Phase terminée'), findsOneWidget);
    expect(find.byKey(const Key('completed_schedule_next')), findsNothing);
  });

  testWidgets('sans résultat : message simple, pas de badge', (tester) async {
    await pump(tester);

    expect(find.byKey(const Key('sessions_remaining_badge')), findsNothing);
    expect(find.byKey(const Key('completed_schedule_next')), findsNothing);
    expect(find.byKey(const Key('completed_back_to_agenda')), findsOneWidget);
  });

  testWidgets('« Retour à l\'agenda » navigue vers /agenda', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('completed_back_to_agenda')));
    await tester.pumpAndSettle();

    expect(find.text('agenda-page'), findsOneWidget);
  });
}
