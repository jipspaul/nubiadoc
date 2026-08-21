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
      expect(find.text('Nobel Biocare'), findsOneWidget);
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
