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
  // #5210 — le RGPD impose de pouvoir prouver la date du consentement : la
  // ligne méta doit afficher un statut daté, pas seulement accordé/refusé.
  testWidgets(
      'écran Consentements : consentement accordé affiche "Accordé le <date>"',
      (tester) async {
    await _pump(tester, [
      Consent(
        purpose: 'soins',
        granted: true,
        grantedAt: DateTime.utc(2026, 3, 12),
      ),
    ]);

    expect(find.text('Accordé le 12 mars 2026'), findsOneWidget);
  });

  testWidgets(
      'écran Consentements : consentement refusé après octroi affiche "Refusé le <date>"',
      (tester) async {
    await _pump(tester, [
      Consent(
        purpose: 'marketing',
        granted: false,
        grantedAt: DateTime.utc(2025, 1, 5),
        revokedAt: DateTime.utc(2026, 8, 4),
      ),
    ]);

    expect(find.text('Refusé le 4 août 2026'), findsOneWidget);
  });

  testWidgets(
      'écran Consentements : consentement jamais accordé affiche "Jamais accordé", sans date',
      (tester) async {
    await _pump(tester, const [
      Consent(purpose: 'ia_scribe', granted: false),
    ]);

    expect(find.text('Jamais accordé'), findsOneWidget);
  });

  testWidgets('écran Consentements : lien "Détails" présent sur chaque carte',
      (tester) async {
    await _pump(tester, const [
      Consent(purpose: 'soins', granted: true),
    ]);

    expect(find.text('Détails'), findsOneWidget);
  });
}
