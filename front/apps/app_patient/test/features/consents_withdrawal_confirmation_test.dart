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

// #6501 — QA-20260905-1 : seul le retrait de `partage_pharmacie` ouvrait la
// feuille de confirmation « conséquences » (maquette design-v2, panneau ②,
// principe n°2). Les trois autres finalités révocables se révoquaient en un
// tap, sans confirmation ni énoncé de conséquence. Vérifie que la feuille
// s'ouvre désormais pour chacune, sans appel PUT immédiat, et que confirmer
// bascule bien la bonne finalité.
void main() {
  const purposes = ['partage_confrere', 'ia_scribe', 'marketing'];

  Future<void> pumpConsentsPage(
    WidgetTester tester,
    MockConsentsCubit cubit,
    List<Consent> consents,
  ) async {
    whenListen(
      cubit,
      const Stream<ConsentsState>.empty(),
      initialState: ConsentsLoaded(consents),
    );
    when(() => cubit.load()).thenAnswer((_) async {});
    when(() => cubit.toggle(any(), any())).thenAnswer((_) async {});

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

  for (final purpose in purposes) {
    testWidgets(
        'retrait de "$purpose" : ouvre la feuille de conséquences, aucun '
        'toggle immédiat', (tester) async {
      final cubit = MockConsentsCubit();
      final consents = [Consent(purpose: purpose, granted: true)];
      await pumpConsentsPage(tester, cubit, consents);

      await tester.tap(find.byKey(Key('consent_$purpose')));
      await tester.pumpAndSettle();

      verifyNever(() => cubit.toggle(any(), any()));
      expect(find.text('Ce qui change'), findsOneWidget);
      expect(find.text('Ce qui ne change pas'), findsOneWidget);
      expect(
        find.byKey(const Key('pharmacy_withdrawal_confirm_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('pharmacy_withdrawal_cancel_button')),
        findsOneWidget,
      );
      // La feuille générique ne porte l'encart « commande en cours » que
      // pour le partage pharmacie (#5212) : jamais pour les autres finalités.
      expect(
        find.byKey(const Key('pharmacy_pending_order_banner')),
        findsNothing,
      );
    });

    testWidgets('retrait de "$purpose" : confirmer bascule cette finalité',
        (tester) async {
      final cubit = MockConsentsCubit();
      final consents = [Consent(purpose: purpose, granted: true)];
      await pumpConsentsPage(tester, cubit, consents);

      await tester.tap(find.byKey(Key('consent_$purpose')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('pharmacy_withdrawal_confirm_button')));
      await tester.pumpAndSettle();

      verify(() => cubit.toggle(purpose, false)).called(1);
    });
  }
}
