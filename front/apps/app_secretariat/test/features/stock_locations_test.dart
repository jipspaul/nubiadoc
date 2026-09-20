//! Tests : `StockLocationsPage`/`StockLocationsBloc` (#7182/#7183) — un
//! onglet par localisation, badge d'alerte scoppé à la salle courante,
//! transfert entre salles.
//!
//! Même convention que `stock_inventory_test.dart` : `pump()`/`pumpAndSettle`
//! plutôt que goldens (aucune infra golden_toolkit dans ce monorepo), pas de
//! `bloc.close()` sur un bloc injecté via `BlocProvider.value`.

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/stock/stock_locations_bloc.dart';
import 'package:app_secretariat/features/stock/stock_locations_event.dart';
import 'package:app_secretariat/features/stock/stock_locations_page.dart';
import 'package:app_secretariat/features/stock/stock_locations_state.dart';

class MockListStockLocationsUseCase extends Mock
    implements ListStockLocationsUseCase {}

class MockListStockItemsUseCase extends Mock implements ListStockItemsUseCase {}

class MockListItemLocationsUseCase extends Mock
    implements ListItemLocationsUseCase {}

class MockCreateStockLocationUseCase extends Mock
    implements CreateStockLocationUseCase {}

class MockTransferStockUseCase extends Mock implements TransferStockUseCase {}

class MockSetItemLocationThresholdUseCase extends Mock
    implements SetItemLocationThresholdUseCase {}

class MockStockLocationsBloc
    extends MockBloc<StockLocationsEvent, StockLocationsState>
    implements StockLocationsBloc {}

const _mainLocation = StockLocation(id: 'loc-main', name: 'Stock principal', isMain: true);
const _room1 = StockLocation(id: 'loc-1', name: 'Salle 1', isMain: false);

const _item = StockItem(
  id: 'item-1',
  reference: 'GANTS-M',
  label: 'Gants latex M',
  unit: 'boite',
  quantityOnHand: 12,
);

Widget _wrap(StockLocationsBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<StockLocationsBloc>.value(
        value: bloc,
        child: const StockLocationsPage(),
      ),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(const StockLocationsLoadRequested());
  });

  group('StockLocationsPage (widget)', () {
    testWidgets('affiche un onglet par localisation', (tester) async {
      final bloc = MockStockLocationsBloc();
      when(() => bloc.state).thenReturn(const StockLocationsLoaded(
        locations: [_mainLocation, _room1],
        items: [_item],
        itemLocations: {
          'item-1': [
            StockItemLocation(
              locationId: 'loc-main',
              locationName: 'Stock principal',
              isMain: true,
              quantity: 10,
            ),
            StockItemLocation(
              locationId: 'loc-1',
              locationName: 'Salle 1',
              isMain: false,
              quantity: 2,
              threshold: 5,
            ),
          ],
        },
      ));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('stock_locations_tab_bar')), findsOneWidget);
      expect(find.text('Stock principal'), findsOneWidget);
      expect(find.text('Salle 1'), findsOneWidget);
    });

    testWidgets(
        'le badge « Sous le seuil » n\'apparaît que dans la salle où le seuil est franchi',
        (tester) async {
      final bloc = MockStockLocationsBloc();
      when(() => bloc.state).thenReturn(const StockLocationsLoaded(
        locations: [_mainLocation, _room1],
        items: [_item],
        itemLocations: {
          'item-1': [
            StockItemLocation(
              locationId: 'loc-main',
              locationName: 'Stock principal',
              isMain: true,
              quantity: 10,
              threshold: 5,
            ),
            StockItemLocation(
              locationId: 'loc-1',
              locationName: 'Salle 1',
              isMain: false,
              quantity: 2,
              threshold: 5,
            ),
          ],
        },
      ));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      // Onglet initial (« Stock principal ») : quantité 10 ≥ seuil 5, pas
      // de badge.
      expect(
        find.descendant(
          of: find.byKey(const Key('stock_location_item_loc-main_item-1')),
          matching: find.byKey(const Key('stock_location_below_threshold')),
        ),
        findsNothing,
      );

      await tester.tap(find.text('Salle 1'));
      await tester.pumpAndSettle();

      // Onglet « Salle 1 » : quantité 2 < seuil 5, badge affiché.
      expect(
        find.descendant(
          of: find.byKey(const Key('stock_location_item_loc-1_item-1')),
          matching: find.byKey(const Key('stock_location_below_threshold')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('valider le transfert dispatch l\'événement attendu',
        (tester) async {
      final bloc = MockStockLocationsBloc();
      when(() => bloc.state).thenReturn(const StockLocationsLoaded(
        locations: [_mainLocation, _room1],
        items: [_item],
        itemLocations: {
          'item-1': [
            StockItemLocation(
              locationId: 'loc-main',
              locationName: 'Stock principal',
              isMain: true,
              quantity: 10,
            ),
            StockItemLocation(
              locationId: 'loc-1',
              locationName: 'Salle 1',
              isMain: false,
              quantity: 2,
            ),
          ],
        },
      ));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      await tester.tap(
        find.byKey(const Key('stock_location_transfer_loc-main_item-1')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('transfer_quantity')),
        '3',
      );
      await tester.tap(find.byKey(const Key('confirm_transfer_button')));
      await tester.pump();

      final captured = verify(() => bloc.add(captureAny())).captured.last
          as StockLocationsTransferRequested;
      expect(captured.itemId, 'item-1');
      expect(captured.fromLocationId, 'loc-main');
      expect(captured.toLocationId, 'loc-1');
      expect(captured.quantity, 3);
    });
  });

  group('StockLocationsBloc (vrai Bloc)', () {
    testWidgets('un transfert met à jour les quantités des deux salles',
        (tester) async {
      final mockListLocations = MockListStockLocationsUseCase();
      final mockListItems = MockListStockItemsUseCase();
      final mockListItemLocations = MockListItemLocationsUseCase();
      final mockCreateLocation = MockCreateStockLocationUseCase();
      final mockTransfer = MockTransferStockUseCase();
      final mockSetThreshold = MockSetItemLocationThresholdUseCase();

      when(() => mockListLocations())
          .thenAnswer((_) async => const Right([_mainLocation, _room1]));
      when(() => mockListItems())
          .thenAnswer((_) async => const Right([_item]));
      when(() => mockListItemLocations('item-1')).thenAnswer((_) async => const Right([
            StockItemLocation(
              locationId: 'loc-main',
              locationName: 'Stock principal',
              isMain: true,
              quantity: 10,
            ),
            StockItemLocation(
              locationId: 'loc-1',
              locationName: 'Salle 1',
              isMain: false,
              quantity: 2,
            ),
          ]));
      when(() => mockTransfer(
            'item-1',
            fromLocationId: 'loc-main',
            toLocationId: 'loc-1',
            quantity: 3,
          )).thenAnswer((_) async => const Right((7, 5)));

      final bloc = StockLocationsBloc(
        listLocations: mockListLocations,
        listItems: mockListItems,
        listItemLocations: mockListItemLocations,
        createLocation: mockCreateLocation,
        transfer: mockTransfer,
        setThreshold: mockSetThreshold,
      );
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.text('GANTS-M · 10 boite'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('stock_location_transfer_loc-main_item-1')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('transfer_quantity')), '3');
      await tester.tap(find.byKey(const Key('confirm_transfer_button')));
      // `pumpAndSettle` : laisse la route du dialog se fermer complètement
      // avant de retaper sur l'onglet — sinon le `DropdownButtonFormField`
      // du dialog (encore en transition de fermeture) laisse une copie
      // masquée de « Salle 1 » dans l'arbre (calcul de largeur interne du
      // dropdown), et le `tap` suivant devient ambigu (2 matches).
      await tester.pumpAndSettle();

      expect(find.text('GANTS-M · 7 boite'), findsOneWidget);

      await tester.tap(find.text('Salle 1'));
      await tester.pumpAndSettle();

      expect(find.text('GANTS-M · 5 boite'), findsOneWidget);
    });
  });
}
