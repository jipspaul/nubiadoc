import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/consents/consents_cubit.dart';
import 'package:app_patient/features/consents/consents_page.dart';

class MockConsentsCubit extends MockCubit<ConsentsState>
    implements ConsentsCubit {}

Future<void> _pump(WidgetTester tester, List<Consent> consents) async {
  final cubit = MockConsentsCubit();
  whenListen(
    cubit,
    const Stream<ConsentsState>.empty(),
    initialState: ConsentsLoaded(consents),
  );
  when(() => cubit.load()).thenAnswer((_) async {});

  GetIt.instance.registerFactory<ConsentsCubit>(() => cubit);
  addTearDown(() => GetIt.instance.reset());

  await tester.pumpWidget(
    MaterialApp(
      theme: NubiaTheme.light,
      home: const Scaffold(body: ConsentsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // #6478 — le lien « Détails » de chaque consentement était un stub
  // (snackbar « bientôt disponibles », aucune donnée). Vérifie qu'il ouvre
  // désormais une feuille avec le détail réel de la finalité tapée.
  testWidgets(
      'écran Consentements : "Détails" ouvre la feuille du consentement, pas le stub snackbar',
      (tester) async {
    await _pump(tester, const [
      Consent(purpose: 'partage_pharmacie', granted: true),
    ]);

    await tester.tap(find.byKey(const Key('consent_details_partage_pharmacie')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('consent_details_sheet_partage_pharmacie')),
      findsOneWidget,
    );
    expect(find.text('Détails du consentement bientôt disponibles.'), findsNothing);
    expect(find.text('Partage avec ma pharmacie'), findsWidgets);
    expect(find.text('Finalité'), findsOneWidget);
    expect(find.text('Base légale'), findsOneWidget);
    expect(
      find.text(
        'Consentement (article 6.1.a du RGPD) — vous pouvez le retirer à '
        'tout moment.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'écran Consentements : la feuille de détail d\'une finalité verrouillée affiche sa base légale',
      (tester) async {
    await _pump(tester, const [
      Consent(purpose: 'soins', granted: true),
    ]);

    await tester.tap(find.byKey(const Key('consent_details_soins')));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const Key('consent_details_sheet_soins'));
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('Requis pour être soigné')),
      findsOneWidget,
    );
  });
}
