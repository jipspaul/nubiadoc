//! Test : `StockImportPage` (#7182/#7183) — import CSV, rapport (lignes
//! importées + erreurs). Pas de bloc ici (action ponctuelle) : use case
//! injecté via `GetIt`, même convention que `sterilization_scan_page_test.dart`.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/stock/stock_import_page.dart';

class _MockImportStockCsvUseCase extends Mock
    implements ImportStockCsvUseCase {}

void main() {
  late _MockImportStockCsvUseCase importCsv;

  setUp(() {
    importCsv = _MockImportStockCsvUseCase();
    GetIt.instance.registerFactory<ImportStockCsvUseCase>(() => importCsv);
    addTearDown(GetIt.instance.reset);
  });

  Widget buildPage() => MaterialApp(
        theme: NubiaTheme.light,
        home: const StockImportPage(),
      );

  testWidgets(
      'un import avec une ligne valide et une ligne rejetée affiche le rapport',
      (tester) async {
    when(() => importCsv('GANTS-M;Gants latex M;10;3.5')).thenAnswer(
      (_) async => const Right(StockImportResult(
        imported: [
          StockImportedLine(
            line: 1,
            itemId: 'item-1',
            reference: 'GANTS-M',
            quantity: 10,
          ),
        ],
        errors: [
          StockImportLineError(
            line: 2,
            raw: 'COMPRESSES;;5',
            error: 'libelle_vide',
          ),
        ],
      )),
    );

    await tester.pumpWidget(buildPage());

    await tester.enterText(
      find.byKey(const Key('stock_import_csv_field')),
      'GANTS-M;Gants latex M;10;3.5',
    );
    await tester.tap(find.byKey(const Key('stock_import_submit_button')));
    await tester.pump();

    expect(
      find.text('1 ligne(s) importée(s) · 1 erreur(s)'),
      findsOneWidget,
    );
    expect(find.textContaining('GANTS-M × 10'), findsOneWidget);

    // Le rapport « Rejetées » est sous le pli de la surface de test — comme
    // un `tap`, un `find.text` par défaut ignore le hors-écran
    // (`skipOffstage: true`) ; `ensureVisible` scrolle la carte en vue
    // avant l'assertion.
    await tester.ensureVisible(
      find.byKey(const Key('stock_import_errors_list'), skipOffstage: false),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('libelle_vide'), findsOneWidget);
  });

  testWidgets('un échec réseau affiche l\'erreur', (tester) async {
    when(() => importCsv(any())).thenAnswer(
      (_) async => const Left(ServerFailure(message: "Impossible d'importer le fichier CSV.")),
    );

    await tester.pumpWidget(buildPage());
    await tester.enterText(
      find.byKey(const Key('stock_import_csv_field')),
      'GANTS-M;Gants latex M;10',
    );
    await tester.tap(find.byKey(const Key('stock_import_submit_button')));
    await tester.pump();

    expect(find.text("Impossible d'importer le fichier CSV."), findsOneWidget);
  });
}
