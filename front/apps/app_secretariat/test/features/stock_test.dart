import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/stock/create_stock_request_dialog.dart';
import 'package:app_secretariat/features/stock/stock_bloc.dart';
import 'package:app_secretariat/features/stock/stock_event.dart';
import 'package:app_secretariat/features/stock/stock_page.dart';
import 'package:app_secretariat/features/stock/stock_state.dart';

class _MockStockBloc extends MockBloc<StockEvent, StockState>
    implements StockBloc {}

void main() {
  group('StockPage — shell maître-détail (#5190)', () {
    late _MockStockBloc bloc;

    setUp(() {
      bloc = _MockStockBloc();
    });

    Widget buildPage() => MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<StockBloc>.value(
            value: bloc,
            child: const StockPage(),
          ),
        );

    final sentRequest = StockRequest(
      id: 'req-1',
      pharmacyId: 'pharma-1',
      pharmacy: const Pharmacy(
        id: 'pharma-1',
        name: 'Pharmacie Auber',
        address: '8 rue Auber, 75009 Paris',
        phone: '01 47 42 18 03',
      ),
      items: const [StockRequestItem(label: 'Gants nitrile', quantity: 2)],
      status: StockRequestStatus.sent,
      createdAt: DateTime(2026, 8, 11, 10, 24),
    );

    final fulfilledRequest = StockRequest(
      id: 'req-2',
      pharmacyId: 'pharma-2',
      items: const [StockRequestItem(label: 'Compresses', quantity: 5)],
      status: StockRequestStatus.fulfilled,
      createdAt: DateTime(2026, 8, 10, 9),
      fulfilledAt: DateTime(2026, 8, 12, 14, 30),
    );

    testWidgets('affiche un squelette en état de chargement', (tester) async {
      when(() => bloc.state).thenReturn(const StockLoading());
      await tester.pumpWidget(buildPage());
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(NubiaSkeletonLoader), findsWidgets);
    });

    testWidgets('affiche un état vide sans demande', (tester) async {
      when(() => bloc.state).thenReturn(const StockLoaded([]));
      await tester.pumpWidget(buildPage());
      expect(find.byType(NubiaEmptyState), findsOneWidget);
    });

    testWidgets('affiche le message d\'erreur', (tester) async {
      when(() => bloc.state).thenReturn(const StockError('Erreur réseau'));
      await tester.pumpWidget(buildPage());
      expect(find.text('Erreur réseau'), findsOneWidget);
    });

    testWidgets('affiche la liste sans panneau détail tant que rien '
        'n\'est sélectionné', (tester) async {
      when(() => bloc.state).thenReturn(StockLoaded([sentRequest]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stock_request_req-1')), findsOneWidget);
      expect(find.byKey(const Key('stock_detail_panel_req-1')), findsNothing);
    });

    testWidgets(
        'sélectionner une demande la surligne et ouvre le panneau détail',
        (tester) async {
      when(() => bloc.state)
          .thenReturn(StockLoaded([sentRequest, fulfilledRequest]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('stock_request_req-1')));
      await tester.pumpAndSettle();

      final panel = find.byKey(const Key('stock_detail_panel_req-1'));
      expect(panel, findsOneWidget);
      final card = tester.widget<NubiaCard>(find.byKey(
        const Key('stock_request_req-1'),
      ));
      expect(card.state, NubiaCardState.selected);

      // En-tête : date + statut + pharmacie (scopé au panneau — la carte de
      // la liste affiche aussi le nom/adresse de la pharmacie).
      expect(find.text('Demande du 11/08 · 10:24'), findsOneWidget);
      expect(
        find.descendant(of: panel, matching: find.text('Pharmacie Auber')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: panel,
          matching: find.text('8 rue Auber, 75009 Paris · 01 47 42 18 03'),
        ),
        findsOneWidget,
      );

      // Section Suivi — libellés exacts (#5190).
      expect(find.text('Demande envoyée'), findsOneWidget);
      expect(find.text('Réponse de la pharmacie'), findsOneWidget);
      expect(find.text('Réception au cabinet'), findsOneWidget);
    });

    testWidgets(
        'affiche — pour les étapes de suivi sans horodatage disponible',
        (tester) async {
      when(() => bloc.state).thenReturn(StockLoaded([sentRequest]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('stock_request_req-1')));
      await tester.pumpAndSettle();

      // sentRequest : ni réponse ni réception -> deux étapes en repli « — ».
      expect(find.text('—'), findsNWidgets(2));
    });

    testWidgets('affiche l\'horodatage réel de réception quand disponible',
        (tester) async {
      when(() => bloc.state).thenReturn(StockLoaded([fulfilledRequest]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('stock_request_req-2')));
      await tester.pumpAndSettle();

      expect(find.text('12/08 · 14:30'), findsOneWidget);
    });

    testWidgets('le bouton de fermeture referme le panneau détail',
        (tester) async {
      when(() => bloc.state).thenReturn(StockLoaded([sentRequest]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('stock_request_req-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stock_detail_panel_req-1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('stock_detail_close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stock_detail_panel_req-1')), findsNothing);
    });

    testWidgets('⏎ ouvre le panneau détail de la première demande',
        (tester) async {
      when(() => bloc.state)
          .thenReturn(StockLoaded([sentRequest, fulfilledRequest]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stock_detail_panel_req-1')), findsOneWidget);
    });

    testWidgets('↑ ↓ change la sélection', (tester) async {
      when(() => bloc.state)
          .thenReturn(StockLoaded([sentRequest, fulfilledRequest]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stock_detail_panel_req-1')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stock_detail_panel_req-2')), findsOneWidget);
      expect(find.byKey(const Key('stock_detail_panel_req-1')), findsNothing);
    });

    // #5188 — bouton toolbar « Nouvelle demande » (⌘N) au lieu du FAB.
    testWidgets(
        'le FAB a disparu, un bouton toolbar « Nouvelle demande » ouvre '
        'la création', (tester) async {
      when(() => bloc.state).thenReturn(StockLoaded([sentRequest]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);

      final button = find.byKey(const Key('new_stock_request_fab'));
      expect(button, findsOneWidget);
      expect(find.descendant(of: button, matching: find.text('Nouvelle demande')),
          findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(CreateStockRequestDialog), findsOneWidget);
    });

    // #5187 — recherche par article / pharmacie.
    testWidgets('affiche le champ de recherche avec le placeholder exact',
        (tester) async {
      when(() => bloc.state)
          .thenReturn(StockLoaded([sentRequest, fulfilledRequest]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stock_search')), findsOneWidget);
      expect(find.text('Article, pharmacie…'), findsOneWidget);
    });

    testWidgets('la recherche filtre par libellé d\'article', (tester) async {
      when(() => bloc.state)
          .thenReturn(StockLoaded([sentRequest, fulfilledRequest]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('stock_search')), 'compresses');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stock_request_req-1')), findsNothing);
      expect(find.byKey(const Key('stock_request_req-2')), findsOneWidget);
    });

    testWidgets('la recherche filtre par nom de pharmacie', (tester) async {
      when(() => bloc.state)
          .thenReturn(StockLoaded([sentRequest, fulfilledRequest]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('stock_search')), 'auber');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stock_request_req-1')), findsOneWidget);
      expect(find.byKey(const Key('stock_request_req-2')), findsNothing);
    });

    testWidgets('affiche un état vide quand la recherche ne trouve rien',
        (tester) async {
      when(() => bloc.state).thenReturn(StockLoaded([sentRequest]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('stock_search')), 'carpules');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stock_request_req-1')), findsNothing);
      expect(find.byType(NubiaEmptyState), findsOneWidget);
    });

    testWidgets('⌘N ouvre la création de demande', (tester) async {
      when(() => bloc.state).thenReturn(StockLoaded([sentRequest]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();

      expect(find.byType(CreateStockRequestDialog), findsOneWidget);
    });
  });
}
