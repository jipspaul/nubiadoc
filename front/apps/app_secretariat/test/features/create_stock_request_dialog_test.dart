import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/stock/create_stock_request_dialog.dart';

class _MockPharmacyDirectoryRepository extends Mock
    implements PharmacyDirectoryRepository {}

void main() {
  group('CreateStockRequestDialog — validation par ligne (#5176)', () {
    late _MockPharmacyDirectoryRepository repository;
    const pharmacy = Pharmacy(id: 'pharma-1', name: 'Pharmacie Auber');

    setUp(() {
      repository = _MockPharmacyDirectoryRepository();
      when(() => repository.search(
            query: any(named: 'query'),
            lat: any(named: 'lat'),
            lng: any(named: 'lng'),
            radiusKm: any(named: 'radiusKm'),
          )).thenAnswer((_) async => const Right([pharmacy]));
      GetIt.instance.registerFactory<SearchPharmaciesUseCase>(
        () => SearchPharmaciesUseCase(repository),
      );
    });

    tearDown(GetIt.instance.reset);

    Future<void> pumpDialog(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: NubiaTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open'),
                onPressed: () => showCreateStockRequestDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('stock_request_pharmacy_picker')));
      await tester.pumpAndSettle();
      final searchField = find.descendant(
        of: find.byType(NubiaSearchBar),
        matching: find.byType(TextField),
      );
      await tester.enterText(searchField, 'auber');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pharmacie Auber'));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'un libellé vide affiche une erreur sur le champ Article et bloque '
        'l\'envoi', (tester) async {
      await pumpDialog(tester);

      await tester.tap(find.byKey(const Key('confirm_create_stock_request_button')));
      await tester.pumpAndSettle();

      expect(find.text('Libellé requis.'), findsOneWidget);
      expect(find.byType(CreateStockRequestDialog), findsOneWidget);
    });

    testWidgets(
        'une quantité non numérique affiche une erreur sur le champ Qté et '
        'bloque l\'envoi', (tester) async {
      await pumpDialog(tester);

      await tester.enterText(
        find.byKey(const Key('stock_item_label_0')),
        'Gants nitrile',
      );
      // numberStepper filtre déjà la saisie non numérique côté champ ;
      // on force néanmoins une quantité nulle pour couvrir `qty <= 0`.
      await tester.enterText(find.byKey(const Key('stock_item_qty_0')), '0');
      await tester.pump();

      await tester.tap(find.byKey(const Key('confirm_create_stock_request_button')));
      await tester.pumpAndSettle();

      expect(find.text('Quantité invalide.'), findsOneWidget);
      expect(find.byType(CreateStockRequestDialog), findsOneWidget);
    });

    testWidgets('une ligne valide ferme le volet sans perte de ligne',
        (tester) async {
      await pumpDialog(tester);

      await tester.enterText(
        find.byKey(const Key('stock_item_label_0')),
        'Gants nitrile',
      );
      await tester.enterText(find.byKey(const Key('stock_item_qty_0')), '3');
      await tester.pump();

      await tester.tap(find.byKey(const Key('confirm_create_stock_request_button')));
      await tester.pumpAndSettle();

      expect(find.byType(CreateStockRequestDialog), findsNothing);
    });
  });
}
