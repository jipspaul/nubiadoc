//! Tests : `ImplantDetailPage`/`ImplantDetailCubit` (#5334). Widget tests
//! couvrent le rendu (boutons d'action + bandeau lecture seule, texte au mot
//! près) ; tests cubit couvrent l'export/partage scopés à l'implant courant
//! — pas de test widget sur l'ouverture/le partage réels du lien, cf.
//! `openDocumentUrl`/`Share.share` jamais exercés au niveau widget ailleurs
//! dans ce monorepo (`implant_passport_test.dart`), seulement au niveau
//! cubit.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/implant_passport/implant_detail_cubit.dart';
import 'package:app_patient/features/implant_passport/implant_detail_page.dart';

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
  late _MockExportImplantPassport exportUseCase;

  setUp(() {
    exportUseCase = _MockExportImplantPassport();
    GetIt.instance.registerFactory<ImplantDetailCubit>(
      () => ImplantDetailCubit(export: exportUseCase),
    );
    addTearDown(GetIt.instance.reset);
  });

  Widget buildPage() => MaterialApp(
        theme: NubiaTheme.light,
        home: const ImplantDetailPage(implant: _implant),
      );

  group('widget', () {
    testWidgets('affiche les deux actions et le bandeau lecture seule',
        (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Exporter cette fiche'), findsOneWidget);
      expect(find.text('Partager avec un professionnel'), findsOneWidget);
      expect(
        find.text(
          'Ces informations viennent de votre dossier médical. '
          'Seul votre praticien peut les modifier.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('implant_detail_readonly_notice')),
        findsOneWidget,
      );
    });
  });

  group('cubit', () {
    ImplantDetailCubit buildCubit() => ImplantDetailCubit(export: exportUseCase);

    test('exportImplant() résout l\'URL scopée à cet implant', () async {
      when(() => exportUseCase(implantId: 'implant-1')).thenAnswer(
        (_) async => const Right('https://storage.example.com/implant-1.pdf'),
      );

      final cubit = buildCubit();
      await cubit.exportImplant('implant-1');

      final state = cubit.state as ImplantDetailUrlReady;
      expect(state.url, 'https://storage.example.com/implant-1.pdf');
      expect(state.action, ImplantDetailAction.export);
      verify(() => exportUseCase(implantId: 'implant-1')).called(1);
      await cubit.close();
    });

    test('shareImplant() résout l\'URL scopée à cet implant', () async {
      when(() => exportUseCase(implantId: 'implant-1')).thenAnswer(
        (_) async => const Right('https://storage.example.com/implant-1.pdf'),
      );

      final cubit = buildCubit();
      await cubit.shareImplant('implant-1');

      final state = cubit.state as ImplantDetailUrlReady;
      expect(state.action, ImplantDetailAction.share);
      verify(() => exportUseCase(implantId: 'implant-1')).called(1);
      await cubit.close();
    });

    test('échec export → état d\'erreur avec le message du repository',
        () async {
      when(() => exportUseCase(implantId: 'implant-1')).thenAnswer(
        (_) async => const Left(ServerFailure(
          message: "Le lien d'export a expiré, réessayez.",
          statusCode: 410,
        )),
      );

      final cubit = buildCubit();
      await cubit.exportImplant('implant-1');

      final state = cubit.state as ImplantDetailError;
      expect(state.message, "Le lien d'export a expiré, réessayez.");
      await cubit.close();
    });

    test('reset() repasse à l\'état neutre', () async {
      when(() => exportUseCase(implantId: 'implant-1')).thenAnswer(
        (_) async => const Right('https://storage.example.com/implant-1.pdf'),
      );

      final cubit = buildCubit();
      await cubit.exportImplant('implant-1');
      cubit.reset();

      expect(cubit.state, const ImplantDetailIdle());
      await cubit.close();
    });
  });
}
