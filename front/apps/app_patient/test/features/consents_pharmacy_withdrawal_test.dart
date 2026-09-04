import 'dart:async';

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
  // #5212 — retirer le partage pharmacie ouvre une feuille de confirmation ;
  // si une commande transmise est en cours, elle porte un encart
  // d'avertissement avec la référence de la commande (jamais codée en dur).
  const consents = [
    Consent(purpose: 'partage_pharmacie', granted: true),
  ];

  Future<void> pumpConsentsPage(
    WidgetTester tester,
    MockConsentsCubit cubit,
  ) async {
    whenListen(
      cubit,
      const Stream<ConsentsState>.empty(),
      initialState: const ConsentsLoaded(consents),
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

  testWidgets(
      "retrait du partage pharmacie : l'encart s'affiche avec la référence "
      "quand une commande est en cours", (tester) async {
    final cubit = MockConsentsCubit();
    when(() => cubit.pendingPharmacyOrderRef())
        .thenAnswer((_) async => 'CMD-4821');
    await pumpConsentsPage(tester, cubit);

    await tester.tap(find.byKey(const Key('consent_partage_pharmacie')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('pharmacy_pending_order_banner')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.info), findsOneWidget);
    expect(
      find.textContaining('La commande CMD-4821', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets(
      "retrait du partage pharmacie : aucun encart sans commande en cours",
      (tester) async {
    final cubit = MockConsentsCubit();
    when(() => cubit.pendingPharmacyOrderRef()).thenAnswer((_) async => null);
    await pumpConsentsPage(tester, cubit);

    await tester.tap(find.byKey(const Key('consent_partage_pharmacie')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('pharmacy_pending_order_banner')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('pharmacy_withdrawal_confirm_button')),
      findsOneWidget,
    );
  });

  testWidgets('retrait du partage pharmacie : confirmer appelle toggle',
      (tester) async {
    final cubit = MockConsentsCubit();
    when(() => cubit.pendingPharmacyOrderRef()).thenAnswer((_) async => null);
    await pumpConsentsPage(tester, cubit);

    await tester.tap(find.byKey(const Key('consent_partage_pharmacie')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('pharmacy_withdrawal_confirm_button')));
    await tester.pumpAndSettle();

    verify(() => cubit.toggle('partage_pharmacie', false)).called(1);
  });

  testWidgets(
      'retrait du partage pharmacie : bascule pas immédiate, blocs '
      '« ce qui change » / « ce qui ne change pas » affichés (#5211)',
      (tester) async {
    final cubit = MockConsentsCubit();
    when(() => cubit.pendingPharmacyOrderRef()).thenAnswer((_) async => null);
    await pumpConsentsPage(tester, cubit);

    await tester.tap(find.byKey(const Key('consent_partage_pharmacie')));
    await tester.pumpAndSettle();

    verifyNever(() => cubit.toggle(any(), any()));
    final sheet = find.byKey(const Key('pharmacy_withdrawal_sheet'));
    expect(find.text('Ce qui change'), findsOneWidget);
    expect(find.text('Ce qui ne change pas'), findsOneWidget);
    // Scopés à la feuille : la carte de consentement en arrière-plan porte
    // aussi une icône `cancel`/`check_circle` (ligne méta statut, #5210).
    expect(
      find.descendant(of: sheet, matching: find.byIcon(Icons.cancel)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: sheet, matching: find.byIcon(Icons.check_circle)),
      findsNWidgets(2),
    );
  });

  testWidgets('retrait du partage pharmacie : annuler ne bascule rien',
      (tester) async {
    final cubit = MockConsentsCubit();
    when(() => cubit.pendingPharmacyOrderRef()).thenAnswer((_) async => null);
    await pumpConsentsPage(tester, cubit);

    await tester.tap(find.byKey(const Key('consent_partage_pharmacie')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('pharmacy_withdrawal_cancel_button')));
    await tester.pumpAndSettle();

    verifyNever(() => cubit.toggle(any(), any()));
    expect(
      find.byKey(const Key('pharmacy_withdrawal_cancel_button')),
      findsNothing,
    );
  });

  // #6488 — un échec du toggle (hors ligne, etc.) ne doit jamais fermer la
  // feuille comme si le retrait avait réussi : la feuille reste ouverte et
  // le SnackBar `toggleError` de la page (#5215) informe l'utilisateur.
  testWidgets(
      'retrait du partage pharmacie : échec réseau -> la feuille reste '
      "ouverte et le message d'erreur s'affiche", (tester) async {
    final cubit = MockConsentsCubit();
    final controller = StreamController<ConsentsState>();
    addTearDown(controller.close);

    when(() => cubit.pendingPharmacyOrderRef()).thenAnswer((_) async => null);
    whenListen(
      cubit,
      controller.stream,
      initialState: const ConsentsLoaded(consents),
    );
    when(() => cubit.load()).thenAnswer((_) async {});
    when(() => cubit.toggle(any(), any())).thenAnswer((_) async {
      controller.add(
        const ConsentsLoaded(
          consents,
          toggleError: 'Erreur réseau. Vérifiez votre connexion.',
        ),
      );
    });

    GetIt.instance.registerFactory<ConsentsCubit>(() => cubit);
    addTearDown(() => GetIt.instance.reset());

    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: ConsentsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('consent_partage_pharmacie')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('pharmacy_withdrawal_confirm_button')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('pharmacy_withdrawal_sheet')),
      findsOneWidget,
    );
    expect(
      find.text('Erreur réseau. Vérifiez votre connexion.'),
      findsOneWidget,
    );
  });
}
