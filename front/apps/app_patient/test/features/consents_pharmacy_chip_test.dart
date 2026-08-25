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

void main() {
  // #5209 — chip pharmacie destinataire sur la carte partage_pharmacie :
  // n'apparaît que si une pharmacie est déclarée, jamais de nom en dur.
  const consents = [
    Consent(purpose: 'partage_pharmacie', granted: true),
  ];

  Future<void> pumpConsentsPage(
    WidgetTester tester,
    MockConsentsCubit cubit, {
    String? pharmacyName,
  }) async {
    whenListen(
      cubit,
      const Stream<ConsentsState>.empty(),
      initialState: ConsentsLoaded(consents, pharmacyName: pharmacyName),
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

  testWidgets(
      'affiche un chip avec le nom de la pharmacie déclarée sur la carte '
      'partage_pharmacie', (tester) async {
    final cubit = MockConsentsCubit();
    await pumpConsentsPage(
      tester,
      cubit,
      pharmacyName: 'Pharmacie du Théâtre',
    );

    expect(find.byKey(const Key('consent_pharmacy_chip')), findsOneWidget);
    expect(find.text('Pharmacie du Théâtre'), findsOneWidget);
    expect(find.byIcon(Icons.store), findsOneWidget);
  });

  testWidgets(
      "n'affiche aucun chip quand aucune pharmacie n'est déclarée",
      (tester) async {
    final cubit = MockConsentsCubit();
    await pumpConsentsPage(tester, cubit, pharmacyName: null);

    expect(find.byKey(const Key('consent_pharmacy_chip')), findsNothing);
    expect(find.byIcon(Icons.store), findsNothing);
  });
}
