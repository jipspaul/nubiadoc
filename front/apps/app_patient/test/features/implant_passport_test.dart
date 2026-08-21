//! Tests : `ImplantPassportPage`/`ImplantPassportCubit` (#4142). Widget tests
//! couvrent l'affichage de la liste (mock de `GET /v1/implant-passport`) et
//! l'état vide ; tests cubit couvrent l'export (`GET
//! /v1/implant-passport/export`, résolution de l'URL signée depuis la
//! redirection 302 côté repository/DTO — pas de test widget sur l'ouverture
//! réelle du lien, cf. `openDocumentUrl`/url_launcher jamais exercé au
//! niveau widget ailleurs dans ce monorepo, seulement au niveau bloc/cubit).
//! Golden test indisponible dans ce monorepo — aucune infra
//! `golden_toolkit`/`goldens/` n'existe ailleurs dans le projet ; substitué
//! par ces tests standard couvrant la même assertion comportementale.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/implant_passport/implant_passport_cubit.dart';
import 'package:app_patient/features/implant_passport/implant_passport_page.dart';

class _MockListImplantPassport extends Mock
    implements ListImplantPassportUseCase {}

class _MockExportImplantPassport extends Mock
    implements ExportImplantPassportUseCase {}

const _implant = ImplantItem(
  id: 'implant-1',
  brand: 'Nobel Biocare',
  lotNumber: 'LOT-42',
  placementDate: '2025-01-15',
  toothPosition: '36',
);

void main() {
  late _MockListImplantPassport listUseCase;
  late _MockExportImplantPassport exportUseCase;

  setUp(() {
    listUseCase = _MockListImplantPassport();
    exportUseCase = _MockExportImplantPassport();
    GetIt.instance.registerFactory<ImplantPassportCubit>(
      () => ImplantPassportCubit(list: listUseCase, export: exportUseCase),
    );
    addTearDown(GetIt.instance.reset);
  });

  Widget buildPage() => MaterialApp(
        theme: NubiaTheme.light,
        home: const ImplantPassportPage(),
      );

  group('widget', () {
    testWidgets('affiche les implants renvoyés par la liste', (tester) async {
      when(() => listUseCase())
          .thenAnswer((_) async => const Right([_implant]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('implant_passport_list')), findsOneWidget);
      expect(find.byKey(const Key('implant_implant-1')), findsOneWidget);
      // #5319 : l'en-tête de carte est le nom anatomique (traduction FDI),
      // pas la marque.
      expect(find.text('Molaire inférieure gauche'), findsOneWidget);
      expect(find.text('36'), findsOneWidget);
      expect(find.text('FDI'), findsOneWidget);
      // #5320 : champs en lignes étiquetées, plus de sous-titre concaténé.
      expect(find.text('Posé le'), findsOneWidget);
      expect(find.text('15 janvier 2025'), findsOneWidget);
      expect(find.text('N° de lot'), findsOneWidget);
      expect(find.text('LOT-42'), findsOneWidget);
      expect(find.textContaining(' · '), findsNothing);
      // Praticien absent sur `_implant` → ligne non rendue.
      expect(find.text('Praticien'), findsNothing);
    });

    testWidgets(
        'affiche la marque en titre et pas de vignette FDI quand '
        'toothPosition est absent', (tester) async {
      const implantWithoutTooth = ImplantItem(
        id: 'implant-5',
        brand: 'Straumann',
      );
      when(() => listUseCase())
          .thenAnswer((_) async => const Right([implantWithoutTooth]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Straumann'), findsOneWidget);
      expect(find.text('FDI'), findsNothing);
    });

    testWidgets(
        'affiche fabricant · modèle sous le nom anatomique quand renseignés',
        (tester) async {
      const implantWithManufacturerModel = ImplantItem(
        id: 'implant-6',
        brand: 'Nobel Biocare',
        toothPosition: '36',
        manufacturer: 'Nobel Biocare',
        model: 'Replace Select',
      );
      when(() => listUseCase()).thenAnswer(
          (_) async => const Right([implantWithManufacturerModel]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Nobel Biocare · Replace Select'), findsOneWidget);
    });

    testWidgets('affiche le praticien sur sa propre ligne quand renseigné',
        (tester) async {
      const implantWithPractitioner = ImplantItem(
        id: 'implant-4',
        brand: 'Nobel Biocare',
        lotNumber: 'NB-4471-22A',
        placementDate: '2026-03-12',
        practitioner: 'Dr Marc Lefèvre',
      );
      when(() => listUseCase())
          .thenAnswer((_) async => const Right([implantWithPractitioner]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Praticien'), findsOneWidget);
      expect(find.text('Dr Marc Lefèvre'), findsOneWidget);
    });

    testWidgets(
        '« Voir la fiche complète » navigue vers le détail de l\'implant '
        'tapé, retour possible ensuite', (tester) async {
      when(() => listUseCase())
          .thenAnswer((_) async => const Right([_implant]));

      ImplantItem? pushedImplant;
      final router = GoRouter(
        initialLocation: '/implant-passport',
        routes: [
          GoRoute(
            path: '/implant-passport',
            builder: (_, __) => const ImplantPassportPage(),
          ),
          GoRoute(
            path: '/implant-passport/:id',
            builder: (_, state) {
              pushedImplant = state.extra as ImplantItem;
              return const Scaffold(body: Text('implant detail'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('implant_detail_link_implant-1')));
      await tester.pumpAndSettle();

      expect(pushedImplant?.id, 'implant-1');
      expect(find.text('implant detail'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('implant_passport_list')), findsOneWidget);
    });

    testWidgets(
        'affiche la carte "Emporter mon passeport" avec le décompte réel '
        'et le bandeau légal', (tester) async {
      const secondImplant = ImplantItem(
        id: 'implant-2',
        brand: 'Straumann',
        lotNumber: 'LOT-99',
      );
      when(() => listUseCase())
          .thenAnswer((_) async => const Right([_implant, secondImplant]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('implant_passport_export_card')),
        findsOneWidget,
      );
      expect(find.text('Emporter mon passeport'), findsOneWidget);
      expect(
        find.text(
          'Un PDF officiel reprenant vos deux implants, leurs références '
          'et leurs numéros de lot.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('implant_passport_export_button')),
          findsOneWidget);
      expect(
        find.byKey(const Key('implant_passport_legal_notice')),
        findsOneWidget,
      );
      expect(
        find.text(
          'La traçabilité des dispositifs médicaux implantables est une '
          'obligation légale : votre praticien conserve ces informations, '
          'et vous en avez une copie permanente.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('aucun implant → état vide dédié', (tester) async {
      when(() => listUseCase()).thenAnswer((_) async => const Right([]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('implant_passport_empty')), findsOneWidget);
      // Le bouton export reste disponible même sans implant (#4142 : l'API
      // n'exige pas d'implant existant pour exporter).
      expect(
        find.byKey(const Key('implant_passport_export_button')),
        findsOneWidget,
      );
    });
  });

  group('cubit', () {
    ImplantPassportCubit buildCubit() =>
        ImplantPassportCubit(list: listUseCase, export: exportUseCase);

    test('export() résout l\'URL signée suivie depuis la redirection 302',
        () async {
      when(() => listUseCase())
          .thenAnswer((_) async => const Right([_implant]));
      when(() => exportUseCase()).thenAnswer(
        (_) async => const Right('https://storage.example.com/signed.pdf'),
      );

      final cubit = buildCubit();
      await cubit.load();
      await cubit.export();

      final state = cubit.state as ImplantPassportLoaded;
      expect(state.exportUrl, 'https://storage.example.com/signed.pdf');
      verify(() => exportUseCase()).called(1);
      await cubit.close();
    });

    test('échec export → état d\'erreur avec le message du repository',
        () async {
      when(() => listUseCase())
          .thenAnswer((_) async => const Right([_implant]));
      when(() => exportUseCase()).thenAnswer(
        (_) async => const Left(ServerFailure(
          message: "Le lien d'export a expiré, réessayez.",
          statusCode: 410,
        )),
      );

      final cubit = buildCubit();
      await cubit.load();
      await cubit.export();

      final state = cubit.state as ImplantPassportError;
      expect(state.message, "Le lien d'export a expiré, réessayez.");
      await cubit.close();
    });
  });
}
