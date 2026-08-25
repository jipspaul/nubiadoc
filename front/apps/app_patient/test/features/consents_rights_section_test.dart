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
  // #5213 — l'écran Consentements doit afficher en bas de liste une section
  // « Vos droits » listant les 3 droits RGPD opposables absents de l'app
  // (export, historique, suppression), chaque ligne tappable.
  testWidgets(
      'écran Consentements : la section « Vos droits » affiche les 3 lignes tappables',
      (tester) async {
    const consents = [
      Consent(purpose: 'soins', granted: true),
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

    expect(find.byKey(const Key('consents_rights_card')), findsOneWidget);
    expect(find.text('Vos droits'), findsOneWidget);

    expect(find.byKey(const Key('right_export_data')), findsOneWidget);
    expect(find.text('Exporter mes données'), findsOneWidget);
    expect(
      find.text('Copie complète, format lisible · sous 30 jours'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.download), findsOneWidget);

    expect(find.byKey(const Key('right_choices_history')), findsOneWidget);
    expect(find.text('Historique de mes choix'), findsOneWidget);
    expect(find.byIcon(Icons.history), findsOneWidget);

    expect(find.byKey(const Key('right_delete_account')), findsOneWidget);
    expect(find.text('Supprimer mon compte'), findsOneWidget);
    expect(
      find.text('Sous réserve des durées légales de conservation'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.person_off), findsOneWidget);

    expect(find.byIcon(Icons.chevron_right), findsNWidgets(3));

    await tester.ensureVisible(find.byKey(const Key('right_export_data')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('right_export_data')));
    await tester.pump();

    expect(
      find.text('Export des données bientôt disponible.'),
      findsOneWidget,
    );
  });
}
