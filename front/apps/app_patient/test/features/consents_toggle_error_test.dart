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
  // #5215 — un échec de toggle (SnackBar via ConsentsLoaded.toggleError) ne
  // doit jamais remplacer consents_list par un NubiaErrorWidget plein écran.
  testWidgets(
      'écran Consentements : un échec de bascule garde la liste affichée, pas de NubiaErrorWidget',
      (tester) async {
    const consents = [
      Consent(purpose: 'marketing', granted: false),
      Consent(purpose: 'soins', granted: true),
    ];

    final cubit = MockConsentsCubit();
    whenListen(
      cubit,
      Stream<ConsentsState>.fromIterable([
        const ConsentsLoaded(
          consents,
          toggleError: 'Échec de la mise à jour.',
        ),
      ]),
      initialState: const ConsentsLoaded(consents, pending: 'marketing'),
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
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('consents_list')), findsOneWidget);
    expect(find.byType(NubiaErrorWidget), findsNothing);
    expect(find.text('Échec de la mise à jour.'), findsOneWidget);
  });

  // Un échec de chargement initial (ConsentsError), lui, reste plein écran.
  testWidgets(
      'écran Consentements : un échec de chargement initial affiche NubiaErrorWidget avec Réessayer',
      (tester) async {
    final cubit = MockConsentsCubit();
    whenListen(
      cubit,
      const Stream<ConsentsState>.empty(),
      initialState: const ConsentsError('Erreur réseau. Vérifiez votre connexion.'),
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

    expect(find.byKey(const Key('consents_list')), findsNothing);
    expect(find.byType(NubiaErrorWidget), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });
}
