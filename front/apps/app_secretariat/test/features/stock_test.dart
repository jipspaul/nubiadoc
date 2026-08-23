import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

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

    testWidgets('affiche un loader en état de chargement', (tester) async {
      when(() => bloc.state).thenReturn(const StockLoading());
      await tester.pumpWidget(buildPage());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
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
  });
}
