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
  // #3706 — les finalités RGPD réellement émises par l'API (soins,
  // partage_pharmacie, partage_confrere, ia_scribe) doivent afficher un
  // libellé lisible, pas leur clé technique brute en snake_case.
  testWidgets(
      'écran Consentements : les finalités réelles affichent un libellé, pas la clé brute',
      (tester) async {
    const consents = [
      Consent(purpose: 'data_processing', granted: true),
      Consent(purpose: 'marketing', granted: false),
      Consent(purpose: 'soins', granted: true),
      Consent(purpose: 'partage_pharmacie', granted: false),
      Consent(purpose: 'partage_confrere', granted: false),
      Consent(purpose: 'ia_scribe', granted: false),
    ];

    final cubit = MockConsentsCubit();
    whenListen(
      cubit,
      const Stream<ConsentsState>.empty(),
      initialState: const ConsentsLoaded(consents),
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

    expect(find.text('Soins'), findsOneWidget);
    expect(find.text('Partage avec ma pharmacie'), findsOneWidget);
    expect(find.text('Partage avec un confrère'), findsOneWidget);
    expect(find.text('Assistance IA (scribe)'), findsOneWidget);

    // Aucune clé technique brute ne doit fuiter dans l'UI.
    expect(find.text('soins'), findsNothing);
    expect(find.text('partage_pharmacie'), findsNothing);
    expect(find.text('partage_confrere'), findsNothing);
    expect(find.text('ia_scribe'), findsNothing);
  });
}
