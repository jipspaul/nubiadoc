// Issue #7251 — depuis « Mes devis », ouvrir un devis passait par un simple
// événement bloc (`FinancialQuoteSelected`) sans jamais écrire d'URL. Le
// retour système (page.goBack) consommait alors la route `/financial`
// elle-même et éjectait le patient vers l'accueil au lieu de sa liste de
// devis. Ce test verrouille que le tap sur une carte écrit bien
// `/financial?id=<quoteId>` dans l'URL (comme le fait déjà le deep-link,
// #7045) et que le bouton « Retour » de l'AppBar la retire à nouveau.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/financial/financial_bloc.dart';
import 'package:app_patient/features/financial/financial_event.dart';
import 'package:app_patient/features/financial/financial_state.dart';
import 'package:app_patient/router/app_router.dart';

class MockTokenStorage extends Mock implements TokenStorage {}

class _MockFinancialBloc extends MockBloc<FinancialEvent, FinancialState>
    implements FinancialBloc {}

final _quote = Quote(
  id: 'q-1',
  quoteRef: 'DEV-0001',
  cabinetId: 'cab-1',
  practitionerName: 'Dr Hugo Marin',
  items: const [],
  totalCents: 15000,
  patientShareCents: 2800,
  depositCents: 4000,
  status: QuoteStatus.sent,
  createdAt: DateTime(2026, 9, 18),
);

void main() {
  setUpAll(() {
    registerFallbackValue(const FinancialLoadRequested());
  });

  late _MockFinancialBloc mockBloc;

  setUp(() async {
    mockBloc = _MockFinancialBloc();
    await GetIt.instance.reset();
    GetIt.instance.registerFactory<FinancialBloc>(() => mockBloc);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets(
    'taper une carte de la liste écrit /financial?id=<quoteId> dans l\'URL',
    (tester) async {
      whenListen(
        mockBloc,
        const Stream<FinancialState>.empty(),
        initialState: FinancialLoaded([_quote]),
      );

      final notifier = RouterNotifier(MockTokenStorage())..markAuthenticated();
      final router = AppRouter.create(notifier);
      router.go('/financial');

      await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('quote_item_q-1')));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/financial?id=q-1',
      );
    },
  );

  testWidgets(
    'le bouton « Retour » de l\'AppBar retire ?id= de l\'URL',
    (tester) async {
      whenListen(
        mockBloc,
        const Stream<FinancialState>.empty(),
        initialState: FinancialQuoteDetail(quote: _quote, quotes: [_quote]),
      );

      final notifier = RouterNotifier(MockTokenStorage())..markAuthenticated();
      final router = AppRouter.create(notifier);
      router.go('/financial?id=q-1');

      await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_appbar_back')));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/financial',
      );
    },
  );

  testWidgets(
    // #7261 : le retour système (geste/bouton OS) ne passe PAS par
    // `btn_appbar_back` — go_router ramène directement l'URL à `/financial`.
    // Comme le `create:` du BlocProvider ne se relance pas pour une même
    // route, seul un mécanisme dans la page peut resynchroniser le bloc.
    'un retour système (URL qui repasse à /financial sans passer par le '
    'bouton) réémet FinancialBackToList',
    (tester) async {
      whenListen(
        mockBloc,
        const Stream<FinancialState>.empty(),
        initialState: FinancialQuoteDetail(quote: _quote, quotes: [_quote]),
      );

      final notifier = RouterNotifier(MockTokenStorage())..markAuthenticated();
      final router = AppRouter.create(notifier);
      router.go('/financial?id=q-1');

      await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();

      router.go('/financial');
      await tester.pumpAndSettle();

      verify(() => mockBloc.add(const FinancialBackToList())).called(1);
    },
  );
}
