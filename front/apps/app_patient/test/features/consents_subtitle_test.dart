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

Future<void> _pump(
  WidgetTester tester,
  ConsentsState state, {
  bool settle = true,
}) async {
  final cubit = MockConsentsCubit();
  whenListen(cubit, const Stream<ConsentsState>.empty(), initialState: state);
  when(() => cubit.load()).thenAnswer((_) async {});

  GetIt.instance.registerFactory<ConsentsCubit>(() => cubit);
  addTearDown(() => GetIt.instance.reset());

  await tester.pumpWidget(
    MaterialApp(
      theme: NubiaTheme.light,
      home: const Scaffold(body: ConsentsPage()),
    ),
  );
  // `ConsentsLoading` affiche un CircularProgressIndicator qui anime en
  // continu : pumpAndSettle ne se termine jamais dans cet état (timeout).
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  // #5207 — le sous-titre récapitule le nombre de consentements accordés vs
  // refusés (maquette design-v2, `patient-consentements.png`), dérivé de
  // `consent.granted`.
  testWidgets(
      'écran Consentements : le titre "Mes consentements" est affiché',
      (tester) async {
    await _pump(tester, const ConsentsLoaded([]));

    expect(find.text('Mes consentements'), findsOneWidget);
  });

  testWidgets(
      'écran Consentements : le sous-titre compte les accordés et refusés '
      'en ConsentsLoaded', (tester) async {
    await _pump(tester, const ConsentsLoaded([
      Consent(purpose: 'soins', granted: true),
      Consent(purpose: 'marketing', granted: true),
      Consent(purpose: 'ia_scribe', granted: false),
      Consent(purpose: 'partage_pharmacie', granted: false),
    ]));

    expect(find.text('2 accordés · 2 refusés'), findsOneWidget);
  });

  testWidgets(
      'écran Consentements : une finalité verrouillée base-légale ON compte '
      'comme accordée, jamais comme refusée', (tester) async {
    await _pump(tester, const ConsentsLoaded([
      Consent(purpose: 'soins', granted: true),
      Consent(purpose: 'data_processing', granted: true),
    ]));

    expect(find.text('2 accordés · 0 refusés'), findsOneWidget);
  });

  testWidgets(
      'écran Consentements : le sous-titre compteur est absent pendant '
      'ConsentsLoading', (tester) async {
    await _pump(tester, const ConsentsLoading(), settle: false);

    expect(find.textContaining('accordés'), findsNothing);
  });

  testWidgets(
      'écran Consentements : le sous-titre compteur est absent en '
      'ConsentsError', (tester) async {
    await _pump(tester, const ConsentsError('Erreur de chargement'));

    expect(find.textContaining('accordés'), findsNothing);
  });
}
