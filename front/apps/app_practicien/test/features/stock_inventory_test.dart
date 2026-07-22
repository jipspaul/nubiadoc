//! Tests : `StockInventoryPage`/`StockInventoryBloc` (#4146) — un item sous
//! le seuil d'alerte affiche un badge distinctif ; soumettre une réception
//! incrémente la quantité affichée. Golden test indisponible dans ce
//! monorepo (aucune infra golden_toolkit/goldens/ n'existe ailleurs) —
//! substitué par ces tests widget/bloc standard couvrant la même assertion
//! comportementale.
//!
//! `pump()` à durée explicite plutôt que `pumpAndSettle()` (même convention
//! que `waiting_room_test.dart`). Ne PAS appeler `bloc.close()` sur un Bloc
//! injecté via `BlocProvider.value` dans un test widget — `.value` ne prend
//! pas possession du cycle de vie du bloc, et un `close()` explicite y bloque
//! indéfiniment (piège découvert en écrivant ce fichier).

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/stock/stock_inventory_bloc.dart';
import 'package:app_practicien/features/stock/stock_inventory_event.dart';
import 'package:app_practicien/features/stock/stock_inventory_page.dart';
import 'package:app_practicien/features/stock/stock_inventory_state.dart';

class MockListStockItemsUseCase extends Mock implements ListStockItemsUseCase {}

class MockAddStockMovementUseCase extends Mock
    implements AddStockMovementUseCase {}

class MockStockInventoryBloc
    extends MockBloc<StockInventoryEvent, StockInventoryState>
    implements StockInventoryBloc {}

const _lowItem = StockItem(
  id: 'item-1',
  reference: 'GANTS-M',
  label: 'Gants latex M',
  unit: 'boite',
  quantityOnHand: 2,
  alertThreshold: 5,
);

const _okItem = StockItem(
  id: 'item-2',
  reference: 'COMPRESSES',
  label: 'Compresses stériles',
  unit: 'boite',
  quantityOnHand: 20,
  alertThreshold: 5,
);

Widget _wrap(StockInventoryBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<StockInventoryBloc>.value(
        value: bloc,
        child: const StockInventoryPage(),
      ),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(const StockInventoryLoadRequested());
  });

  group('StockInventoryPage (widget)', () {
    testWidgets('un item sous le seuil d\'alerte affiche un badge distinctif',
        (tester) async {
      final bloc = MockStockInventoryBloc();
      when(() => bloc.state)
          .thenReturn(const StockInventoryLoaded([_lowItem, _okItem]));
      await tester.pumpWidget(_wrap(bloc));

      expect(find.byKey(const Key('stock_item_item-1')), findsOneWidget);
      expect(find.byKey(const Key('stock_item_item-2')), findsOneWidget);

      // Le badge n'apparaît que pour l'item sous le seuil.
      expect(
        find.descendant(
          of: find.byKey(const Key('stock_item_item-1')),
          matching: find.byKey(const Key('stock_item_below_threshold')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('stock_item_item-2')),
          matching: find.byKey(const Key('stock_item_below_threshold')),
        ),
        findsNothing,
      );
    });

    testWidgets('la quantité affichée reflète quantityOnHand de l\'état',
        (tester) async {
      final bloc = MockStockInventoryBloc();
      when(() => bloc.state).thenReturn(const StockInventoryLoaded([
        StockItem(
          id: 'item-1',
          reference: 'GANTS-M',
          label: 'Gants latex M',
          unit: 'boite',
          quantityOnHand: 12,
          alertThreshold: 5,
        ),
      ]));
      await tester.pumpWidget(_wrap(bloc));

      expect(find.text('GANTS-M · 12 boite'), findsOneWidget);
    });

    testWidgets(
        'valider le formulaire de réception dispatch le mouvement attendu',
        (tester) async {
      final bloc = MockStockInventoryBloc();
      when(() => bloc.state).thenReturn(const StockInventoryLoaded([_lowItem]));
      await tester.pumpWidget(_wrap(bloc));

      await tester.tap(find.byKey(const Key('stock_item_movement_item-1')));
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('stock_movement_quantity')),
        '10',
      );
      await tester.tap(find.byKey(const Key('confirm_stock_movement_button')));
      await tester.pump();

      // StockInventoryMovementRequested n'a pas d'égalité de valeur (pas
      // Equatable) — capture + assertions champ à champ plutôt qu'une
      // comparaison const (même contrainte que WaitingRoomLoadRequested,
      // cf. waiting_room_test.dart).
      final captured = verify(() => bloc.add(captureAny())).captured.last
          as StockInventoryMovementRequested;
      expect(captured.itemId, 'item-1');
      expect(captured.delta, 10);
      expect(captured.reason, 'reception');
    });
  });

  group('StockInventoryBloc (via StockInventoryPage, vrai Bloc)', () {
    testWidgets('une réception incrémente la quantité affichée',
        (tester) async {
      final mockList = MockListStockItemsUseCase();
      final mockAddMovement = MockAddStockMovementUseCase();
      when(() => mockList())
          .thenAnswer((_) async => const Right([_lowItem, _okItem]));
      when(() => mockAddMovement(
            'item-1',
            delta: 10,
            reason: 'reception',
          )).thenAnswer((_) async => const Right(12));

      final bloc =
          StockInventoryBloc(list: mockList, addMovement: mockAddMovement);
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.text('GANTS-M · 2 boite'), findsOneWidget);

      await tester.tap(find.byKey(const Key('stock_item_movement_item-1')));
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('stock_movement_quantity')),
        '10',
      );
      await tester.tap(find.byKey(const Key('confirm_stock_movement_button')));
      await tester.pump();

      expect(find.text('GANTS-M · 12 boite'), findsOneWidget);
      verify(() => mockAddMovement('item-1', delta: 10, reason: 'reception'))
          .called(1);
    });
  });
}
